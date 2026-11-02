import CmuxSettings
import Foundation

extension TerminalNotificationStore {
    /// Both notification effect lanes use the same ordering path. The caller
    /// already applied mute, cooldown, effect policy, and the reorder setting.
    func applySidebarOrdering(for notification: TerminalNotification, effects: TerminalNotificationPolicyEffects) {
        effects.applySidebarOrdering(defaults: .standard, workspaceId: notification.tabId) {
            AppDelegate.shared?.tabManagerFor(tabId: notification.tabId)?
                .moveTabToTopForNotification(notification.tabId)
        }
    }
}

extension TerminalNotificationPolicyEffects {
    /// `off` never reorders. `notifications` moves the workspace at once.
    /// `agentActivity` routes the move through the shared activity throttle,
    /// which moves the workspace itself.
    @MainActor
    func applySidebarOrdering(
        defaults: UserDefaults,
        workspaceId: UUID,
        controller: WorkspaceActivityReorderController? = nil,
        moveLocalWorkspace: () -> Void
    ) {
        guard reorderWorkspace else { return }
        switch UserDefaultsSettingsClient(defaults: defaults).value(for: SettingCatalog().app.reorderOnNotification) {
        case .off:
            return
        case .notifications:
            moveLocalWorkspace()
        case .agentActivity:
            (controller ?? .shared).notificationRequestsReorder(workspaceId: workspaceId)
        }
    }
}
