import AppKit
import CmuxSwiftRenderUI

/// Focus Sidebar (cx-zjtn.5): the workspace list takes the keyboard, as in
/// cmux-next. The shortcut toggles: pressing it again hands the keyboard back.
///
/// Native sidebar: the workspace table becomes first responder; Down/Up
/// select the next/previous workspace, Return or Escape hand the keyboard
/// back to the selected workspace.
///
/// Custom JS sidebar (the fork's compact sidebar): "sidebar keyboard mode"
/// (``CustomSidebarKeyboardMode``). The window's first responder is cleared
/// so the terminal gets no keys, and the shortcut router hands every
/// key-down to the sidebar program's `onKey` handler through the window's
/// ``CustomSidebarKeyboardChannel``. The program owns the cursor over its
/// own rows; the host only enters/leaves the mode and moves focus.
extension AppDelegate {
    /// Toggles keyboard focus on the window's workspace sidebar, revealing it
    /// first when hidden.
    @discardableResult
    func focusSidebarForKeyboard(preferredWindow: NSWindow?) -> Bool {
        guard let context = preferredRegisteredMainWindowContext(preferredWindow: preferredWindow),
              let window = resolvedWindow(for: context) else {
            return false
        }
        let mode = CustomSidebarKeyboardMode.shared
        if mode.isActive(in: window) {
            endCustomSidebarKeyboardMode(restoreFocus: true)
            return true
        }
        if let table = window.firstResponder as? SidebarWorkspaceTableViewImpl,
           !table.isHiddenOrHasHiddenAncestor {
            focusSelectedWorkspacePanel(manager: context.tabManager, window: window)
            return true
        }
        if !context.sidebarState.isVisible {
            context.sidebarState.toggle()
        }
        let channel = context.sidebarState.customSidebarKeyboard
        if channel.acceptsKeys {
            beginCustomSidebarKeyboardMode(in: window, channel: channel)
        } else if Self.sidebarTable(in: window.contentView) == nil, context.sidebarState.isVisible {
            // A custom sidebar revealed by this call mounts on a later pass.
            beginCustomSidebarKeyboardModeWhenMounted(in: window, channel: channel, attemptsLeft: 5)
        } else {
            focusSidebarTable(in: window, attemptsLeft: 5)
        }
        return true
    }

    /// Collapses every workspace group in the window, or expands them all
    /// when none is open. Returns false (event not consumed) when the window
    /// has no groups.
    @discardableResult
    func toggleCollapseAllWorkspaceGroups(preferredWindow: NSWindow?) -> Bool {
        guard let context = preferredRegisteredMainWindowContext(preferredWindow: preferredWindow) else {
            return false
        }
        let manager = context.tabManager
        let groups = manager.workspaceGroups
        guard !groups.isEmpty else { return false }
        let collapse = groups.contains { !$0.isCollapsed }
        for group in groups where group.isCollapsed != collapse {
            manager.setWorkspaceGroupCollapsed(groupId: group.id, isCollapsed: collapse)
        }
        return true
    }

    /// Every key-down while a window is in custom-sidebar keyboard mode (the
    /// shortcut router asks first). Returns whether the key was consumed; a
    /// key that ends the mode without being handled goes on as usual.
    func handleCustomSidebarKeyboardModeKey(_ event: NSEvent, in window: NSWindow?) -> Bool {
        let mode = CustomSidebarKeyboardMode.shared
        guard let home = mode.window, let channel = mode.channel else { return false }
        guard let window, window === home else {
            // Typing in another window (or a panel) leaves the mode.
            endCustomSidebarKeyboardMode(restoreFocus: false)
            return false
        }
        if matchConfiguredShortcut(event: event, action: .focusSidebar) {
            endCustomSidebarKeyboardMode(restoreFocus: true)
            return true
        }
        if matchConfiguredShortcut(event: event, action: .toggleCollapseAllWorkspaceGroups) {
            _ = toggleCollapseAllWorkspaceGroups(preferredWindow: window)
            return true
        }
        // An inline rename field in the sidebar keeps its own keys.
        if window.firstResponder is NSText {
            return false
        }
        guard let key = SidebarKeyPress(event: event) else {
            endCustomSidebarKeyboardMode(restoreFocus: true)
            return false
        }
        let result = channel.send(key)
        guard result.handled else {
            endCustomSidebarKeyboardMode(restoreFocus: true)
            return false
        }
        if let openId = result.openWorkspaceId {
            endCustomSidebarKeyboardMode(restoreFocus: false)
            openWorkspaceFromSidebarKeyboard(id: openId, in: window)
        } else if result.exit {
            endCustomSidebarKeyboardMode(restoreFocus: true)
        }
        return true
    }

    func endCustomSidebarKeyboardMode(restoreFocus: Bool) {
        guard let ended = CustomSidebarKeyboardMode.shared.end() else { return }
        ended.channel.setKeyboardMode(false)
        guard restoreFocus, let window = ended.window,
              let manager = contextForMainTerminalWindow(window)?.tabManager else { return }
        focusSelectedWorkspacePanel(manager: manager, window: window)
    }

    // MARK: - Custom sidebar keyboard mode

    private func beginCustomSidebarKeyboardMode(in window: NSWindow, channel: CustomSidebarKeyboardChannel) {
        // One window at a time; another window's mode just ends.
        endCustomSidebarKeyboardMode(restoreFocus: false)
        // The terminal (or browser) loses the keyboard while the list has it.
        _ = window.makeFirstResponder(nil)
        CustomSidebarKeyboardMode.shared.begin(
            window: window,
            channel: channel,
            onClickOutside: { [weak self] in self?.endCustomSidebarKeyboardMode(restoreFocus: false) },
            onWindowResign: { [weak self] in self?.endCustomSidebarKeyboardMode(restoreFocus: false) }
        )
        channel.setKeyboardMode(true)
    }

    private func beginCustomSidebarKeyboardModeWhenMounted(
        in window: NSWindow,
        channel: CustomSidebarKeyboardChannel,
        attemptsLeft: Int
    ) {
        guard attemptsLeft > 1 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak window] in
            guard let self, let window else { return }
            if channel.acceptsKeys {
                self.beginCustomSidebarKeyboardMode(in: window, channel: channel)
            } else if let table = Self.sidebarTable(in: window.contentView), !table.isHiddenOrHasHiddenAncestor {
                window.makeFirstResponder(table)
            } else {
                self.beginCustomSidebarKeyboardModeWhenMounted(
                    in: window,
                    channel: channel,
                    attemptsLeft: attemptsLeft - 1
                )
            }
        }
    }

    private func openWorkspaceFromSidebarKeyboard(id: String, in window: NSWindow) {
        guard let manager = contextForMainTerminalWindow(window)?.tabManager else { return }
        if let uuid = UUID(uuidString: id),
           let workspace = manager.tabs.first(where: { $0.id == uuid }),
           manager.selectedTabId != uuid {
            manager.selectWorkspace(workspace)
        }
        focusSelectedWorkspacePanel(manager: manager, window: window)
    }

    // MARK: - Native sidebar

    /// Handles a key typed while the workspace list has focus.
    ///
    /// - Returns: `false` for keys the list leaves to AppKit.
    func handleSidebarKeyboardKey(_ event: NSEvent, in table: NSTableView) -> Bool {
        guard event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift]),
              let window = table.window,
              let manager = contextForMainTerminalWindow(window)?.tabManager else {
            return false
        }
        switch event.keyCode {
        case 125: // Down
            manager.selectNextTab()
        case 126: // Up
            manager.selectPreviousTab()
        case 36, 76, 53: // Return, keypad Enter, Escape
            focusSelectedWorkspacePanel(manager: manager, window: window)
            return true
        default:
            return false
        }
        // Selecting a workspace restores its panel's focus; keep the list
        // focused so the next arrow keeps stepping.
        keepKeyboard(on: table, in: window)
        return true
    }

    private func focusSidebarTable(in window: NSWindow, attemptsLeft: Int) {
        if let table = Self.sidebarTable(in: window.contentView), !table.isHiddenOrHasHiddenAncestor {
            window.makeFirstResponder(table)
            return
        }
        // A sidebar revealed by this call mounts on a later pass.
        guard attemptsLeft > 1 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak window] in
            guard let window else { return }
            self?.focusSidebarTable(in: window, attemptsLeft: attemptsLeft - 1)
        }
    }

    private func keepKeyboard(on table: NSTableView, in window: NSWindow) {
        window.makeFirstResponder(table)
        for delay in [0.0, 0.15] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak table, weak window] in
                guard let table, let window, window.firstResponder !== table else { return }
                window.makeFirstResponder(table)
            }
        }
    }

    private func focusSelectedWorkspacePanel(manager: TabManager, window: NSWindow) {
        _ = window.makeFirstResponder(nil)
        guard let workspace = manager.selectedWorkspace,
              let panelId = workspace.focusedPanelId,
              let panel = workspace.panels[panelId] else {
            return
        }
        noteMainPanelKeyboardFocusIntent(workspaceId: workspace.id, panelId: panelId, in: window)
        workspace.focusPanel(panelId, focusIntent: panel.preferredFocusIntentForActivation())
    }

    private static func sidebarTable(in view: NSView?) -> SidebarWorkspaceTableViewImpl? {
        guard let view else { return nil }
        if let table = view as? SidebarWorkspaceTableViewImpl { return table }
        for subview in view.subviews {
            if let table = sidebarTable(in: subview) { return table }
        }
        return nil
    }
}

/// The one window (at most) in custom-sidebar keyboard mode, plus the
/// monitors that end it: a click outside the sidebar column, or the window
/// losing key status.
@MainActor
final class CustomSidebarKeyboardMode {
    static let shared = CustomSidebarKeyboardMode()

    struct Ended {
        weak var window: NSWindow?
        let channel: CustomSidebarKeyboardChannel
    }

    private struct Session {
        weak var window: NSWindow?
        let channel: CustomSidebarKeyboardChannel
        let mouseMonitor: Any?
        let resignObserver: NSObjectProtocol?
    }

    private var session: Session?

    var window: NSWindow? { session?.window }
    var channel: CustomSidebarKeyboardChannel? { session?.channel }
    var isActive: Bool { session != nil }

    func isActive(in window: NSWindow) -> Bool {
        session?.window === window
    }

    func begin(
        window: NSWindow,
        channel: CustomSidebarKeyboardChannel,
        onClickOutside: @escaping @MainActor () -> Void,
        onWindowResign: @escaping @MainActor () -> Void
    ) {
        let mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak window, weak channel] event in
            MainActor.assumeIsolated {
                // Clicks inside the sidebar column keep the mode (rows,
                // folder headers); anything else ends it and proceeds.
                let inSidebar = event.window === window
                    && channel?.columnContains(windowPoint: event.locationInWindow) == true
                if !inSidebar { onClickOutside() }
            }
            return event
        }
        let resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { onWindowResign() }
        }
        session = Session(window: window, channel: channel, mouseMonitor: mouseMonitor, resignObserver: resignObserver)
    }

    /// Ends the session, removing its monitors. Returns what ended, or nil
    /// when no session was active.
    func end() -> Ended? {
        guard let current = session else { return nil }
        session = nil
        if let monitor = current.mouseMonitor { NSEvent.removeMonitor(monitor) }
        if let observer = current.resignObserver { NotificationCenter.default.removeObserver(observer) }
        return Ended(window: current.window, channel: current.channel)
    }
}
