import AppKit
import CmuxCloud
import Foundation

/// Binds the shared Cloud menu (status item and main-menu Cloud menu) to the
/// app's existing Cloud entrypoints. No verb here has its own implementation:
/// each one calls the action the File menu, palette, sidebar or CLI already use.
extension AppDelegate {
    /// What a Cloud menu should show right now.
    @MainActor
    func cloudMenuContext(model: CloudMenuModel? = nil) -> CloudMenuContext {
        let model = model ?? .shared
        _ = model
        // Sign-in went with Sources/Auth (Phase 9.13), so there is never an account.
        return CloudMenuContext(account: .unavailable)
    }

    /// The Cloud verbs. `fromStatusItem` brings cmux forward first, because a
    /// status item click leaves the app inactive and Cloud creation only
    /// navigates a window that is key when it finishes.
    @MainActor
    func cloudMenuActions(model: CloudMenuModel? = nil, fromStatusItem: Bool) -> CloudMenuActions {
        let model = model ?? .shared
        let source = fromStatusItem ? "menuBarExtra.cloud" : "mainMenu.cloud"
        let window: @MainActor () -> NSWindow? = { [weak self] in
            if fromStatusItem { return self?.showMainWindowFromMenuBar() }
            return NSApp.keyWindow ?? NSApp.mainWindow
        }
        let rowActions = MachineRowActions.bound(onDidMutate: { [weak model] in model?.refresh() })
        let machine = CloudMachineMenuVerbs(
            openShell: { id in _ = window(); rowActions.openShell(id) },
            newWorkspace: { [weak self] id in
                let preferred = window()
                guard let self, let manager = self.activeTabManagerForCommands(preferredWindow: preferred),
                      self.performNewCloudWorkspaceOnCurrentMachineAction(tabManager: manager, vmID: id) else {
                    NSSound.beep()
                    return
                }
            },
            openDesktop: { id in _ = window(); rowActions.openDesktop(id) },
            runCommand: { id, verb in _ = window(); rowActions.runCommand(id, verb) },
            promptRename: { machine in _ = window(); rowActions.promptRename(machine) },
            copyToPasteboard: { text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            },
            confirmDelete: { machine in _ = window(); rowActions.confirmDelete(machine) },
            promptUpgrade: { _ = window(); rowActions.promptUpgrade() },
            fork: { machine in
                if !NewMachineSheetPresenter.shared.startFork(
                    sourceMachineID: machine.id, sourceName: machine.displayName, preferredWindow: window()
                ) { NSSound.beep() }
            }
        )
        return CloudMenuActions(
            signIn: {},
            signOut: {},
            selectTeam: { _ in },
            newWorkspace: { [weak self] in
                let preferred = window()
                if self?.performNewCloudWorkspaceOnResolvedMachineAction(preferredWindow: preferred, debugSource: source) != true {
                    NSSound.beep()
                }
            },
            newMachine: { [weak self] in
                let preferred = window()
                _ = self?.performNewCloudMachineAction(preferredWindow: preferred, debugSource: source)
            },
            showMachines: { [weak self] in
                let preferred = window()
                if self?.revealCloudMachinesSidebar(preferredWindow: preferred) != true { NSSound.beep() }
            },
            openDashboard: {
                _ = NSWorkspace.shared.open(AuthEnvironment.apiBaseURL.appendingPathComponent("dashboard/cloud"))
            },
            showDiagnostics: { [weak self] in
                if fromStatusItem { NSApp.activate() }
                self?.showCloudDiagnostics()
            },
            upgrade: {},
            retry: { [weak model] in model?.refresh() },
            machine: machine
        )
    }

    /// Opens the right sidebar on its Cloud machines tab, the same reveal the
    /// team picker uses.
    @MainActor
    @discardableResult
    func revealCloudMachinesSidebar(preferredWindow: NSWindow?) -> Bool {
        guard RightSidebarMode.machines.isAvailable(),
              let context = preferredRegisteredMainWindowContext(preferredWindow: preferredWindow),
              let state = context.fileExplorerState else { return false }
        state.mode = .machines
        state.setVisible(true)
        _ = focusRightSidebarInActiveMainWindow(
            mode: .machines,
            focusFirstItem: false,
            preferredWindow: context.window ?? preferredWindow
        )
        return true
    }
}
