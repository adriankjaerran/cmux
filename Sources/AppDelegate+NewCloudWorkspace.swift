import AppKit
import CmuxCloud
import CmuxCloudMachines
import CmuxProductAnalytics
import Foundation

// MARK: - Cloud creation actions

extension AppDelegate {
    /// Cloud is off in this fork: there is no Cloud workspace to create.
    @discardableResult
    func performNewCloudWorkspaceOnResolvedMachineAction(
        tabManager preferredTabManager: TabManager? = nil,
        preferredWindow: NSWindow? = nil,
        debugSource: String = "newCloudWorkspace",
        destination: CloudWorkspaceGroupDestination? = nil
    ) -> Bool {
        false
    }

    /// Cloud is off in this fork: there is no Cloud machine to create on.
    @discardableResult
    func performNewCloudWorkspaceOnCurrentMachineAction(
        tabManager: TabManager,
        vmID: String,
        destination: CloudWorkspaceGroupDestination? = nil
    ) -> Bool {
        false
    }

    /// Places a machine's reservation immediately; later provisioning cannot undo user navigation.
    @discardableResult
    func performNewCloudMachineAction(
        tabManager preferredTabManager: TabManager? = nil,
        event: NSEvent? = nil,
        preferredWindow: NSWindow? = nil,
        debugSource: String = "newCloudMachine",
        destination: CloudWorkspaceGroupDestination? = nil
    ) -> Bool {
        let introductionWindow = preferredWindow
            ?? preferredTabManager.flatMap { mainWindowContext(for: $0) }.flatMap { resolvedWindow(for: $0) }
            ?? event?.window
        if introduceCloudIfNeeded(
            over: introductionWindow,
            trigger: .newCloudMachine,
            resume: { [weak self, weak preferredTabManager, weak introductionWindow] in
                _ = self?.performNewCloudMachineAction(
                    tabManager: preferredTabManager,
                    preferredWindow: introductionWindow,
                    debugSource: "\(debugSource).afterEnable",
                    destination: destination
                )
            }
        ) {
            return true
        }
        guard let operationController = cloudWorkspaceOperationController,
              operationController.isCurrentlyAvailable else { return false }
        let context = preferredTabManager.flatMap { mainWindowContext(for: $0) }
            ?? preferredWindow.flatMap { contextForMainWindow($0) }
            ?? event.flatMap { mainWindowContext(forShortcutEvent: $0, debugSource: debugSource) }
            ?? preferredMainWindowContextForWorkspaceCreation(event: event, debugSource: debugSource)
        let hostWindow = context.flatMap { resolvedWindow(for: $0) }
            ?? preferredWindow ?? event?.window ?? NSApp.keyWindow ?? NSApp.mainWindow
        guard let presenter = newMachineSheetPresenter else { return false }
        return operationController.start {
            _ = await presenter.presentNewMachineFetchingPlan(preferredWindow: hostWindow) { workspaceID in
                guard operationController.isCurrentlyAvailable else { return }
                destination?.apply(workspaceID: workspaceID)
            }
        }
    }

    func cloudCreationGate() -> CloudCreationGate {
        CloudCreationGate.resolve(
            isAvailable: CloudMachinesFeature.isAvailable,
            isEnabled: CloudMachinesFeature.isEnabled,
            canRunCloudOperations: cloudWorkspaceOperationController?.isCurrentlyAvailable,
            isAuthInProgress: auth?.accountFlow.isWorkingOnAuth == true
        )
    }

    /// The sidebar footer Cloud button: reveals Cloud Machines in the right
    /// sidebar on every press (never toggles it closed), and while Cloud is off
    /// or signed out also reopens the welcome card, whose next step routes to
    /// sign-in, Upgrade or Enable from the account's plan.
    func performSidebarCloudButtonAction(preferredWindow: NSWindow?) {
        let window = preferredWindow ?? NSApp.keyWindow ?? NSApp.mainWindow
        SidebarCloudButtonAction(
            isAvailable: { CloudMachinesFeature.isAvailable },
            isEnabled: { [weak self] in self?.cloudCreationGate() != .introduceCloud },
            revealMachines: { [weak self] in
                _ = self?.focusRightSidebarInActiveMainWindow(mode: .machines, preferredWindow: window)
            },
            presentIntroduction: { [weak self] in
                self?.cloudWelcomeWindowController.presentIntroduction(over: window)
            },
            analytics: .app
        ).perform()
    }

    /// Cloud creation shortcuts and menu rows introduce Cloud while it is off
    /// or signed out. Returning users skip the card and take its next step;
    /// Enable then resumes `resume`.
    private func introduceCloudIfNeeded(
        over window: NSWindow?,
        trigger: CloudWelcomeTrigger,
        resume: @escaping @MainActor () -> Void
    ) -> Bool {
        guard cloudCreationGate() == .introduceCloud else { return false }
        cloudWelcomeWindowController.present(
            over: window ?? NSApp.keyWindow ?? NSApp.mainWindow,
            trigger: trigger,
            onEnabled: resume
        )
        return true
    }
}
