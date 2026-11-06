import AppKit
import CmuxSwiftRenderUI

/// Focus Sidebar (cx-zjtn.5): the workspace list takes the keyboard, as in
/// cmux-next. The shortcut toggles: pressing it again hands the keyboard back.
///
/// The left sidebar is always a custom JS sidebar (the fork's compact sidebar): "sidebar keyboard mode"
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
        if !context.sidebarState.isVisible {
            context.sidebarState.toggle()
        }
        let channel = context.sidebarState.customSidebarKeyboard
        if channel.acceptsKeys {
            beginCustomSidebarKeyboardMode(in: window, channel: channel)
        } else if context.sidebarState.isVisible {
            // A custom sidebar revealed by this call mounts on a later pass.
            beginCustomSidebarKeyboardModeWhenMounted(in: window, channel: channel, attemptsLeft: 5)
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
        if let closeId = result.closeWorkspaceId {
            confirmCloseWorkspaceFromSidebarKeyboard(id: closeId, in: window)
        } else if let openId = result.openWorkspaceId {
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
            } else {
                self.beginCustomSidebarKeyboardModeWhenMounted(
                    in: window,
                    channel: channel,
                    attemptsLeft: attemptsLeft - 1
                )
            }
        }
    }

    /// Backspace in sidebar keyboard mode: a small "Delete workspace?" sheet
    /// (Return or click deletes, Esc cancels), then back into keyboard mode so
    /// the next row can be deleted the same way.
    private func confirmCloseWorkspaceFromSidebarKeyboard(id: String, in window: NSWindow) {
        guard let manager = contextForMainTerminalWindow(window)?.tabManager,
              let uuid = UUID(uuidString: id),
              let workspace = manager.tabs.first(where: { $0.id == uuid }) else { return }
        guard manager.canCloseWorkspace(workspace, allowPinned: true) else {
            NSSound.beep()
            return
        }
        // The sheet takes key status, which would end the mode anyway.
        endCustomSidebarKeyboardMode(restoreFocus: false)
        DispatchQueue.main.async { [weak self, weak window, weak manager, weak workspace] in
            guard let self, let window, let manager, let workspace else { return }
            let alert = NSAlert()
            alert.alertStyle = .warning
            let title = workspace.title.trimmingCharacters(in: .whitespacesAndNewlines)
            alert.messageText = title.isEmpty
                ? String(localized: "sidebar.keyboard.deleteWorkspace.untitled", defaultValue: "Delete this workspace?")
                : String(
                    format: String(localized: "sidebar.keyboard.deleteWorkspace.title", defaultValue: "Delete workspace “%@”?"),
                    title
                )
            alert.informativeText = String(
                localized: "sidebar.keyboard.deleteWorkspace.message",
                defaultValue: "Its terminals and tabs will be closed."
            )
            let deleteButton = alert.addButton(withTitle: String(localized: "sidebar.keyboard.deleteWorkspace.delete", defaultValue: "Delete"))
            deleteButton.keyEquivalent = "\r"
            deleteButton.hasDestructiveAction = true
            let cancelButton = alert.addButton(withTitle: String(localized: "common.cancel", defaultValue: "Cancel"))
            cancelButton.keyEquivalent = "\u{1b}"
            alert.window.initialFirstResponder = deleteButton
            let confirmed = alert.runCmuxModal(presentingWindow: window) == .alertFirstButtonReturn
            if confirmed {
                manager.closeWorkspaceConfirmedFromSidebarKeyboard(workspace)
            }
            // Back to the list (the cursor lands on the now-selected row).
            if window.isVisible, !CustomSidebarKeyboardMode.shared.isActive(in: window) {
                _ = self.focusSidebarForKeyboard(preferredWindow: window)
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
