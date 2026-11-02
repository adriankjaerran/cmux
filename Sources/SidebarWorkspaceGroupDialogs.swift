import AppKit

/// Confirmation dialog for destructive group deletion.
@MainActor
func confirmDeleteWorkspaceGroup(groupName: String, memberCount: Int) -> Bool {
    let title = String(
        localized: "dialog.deleteGroup.title",
        defaultValue: "Delete this group?"
    )
    let message: String?
    if memberCount <= 0 {
        message = nil
    } else if memberCount == 1 {
        let format = String(
            localized: "dialog.deleteGroup.message.lone",
            defaultValue: "Delete the group \u{201C}%@\u{201D} and close its workspace?"
        )
        message = String.localizedStringWithFormat(format, groupName)
    } else if memberCount == 2 {
        let format = String(
            localized: "dialog.deleteGroup.message.one",
            defaultValue: "Delete the group \u{201C}%@\u{201D} and close its 2 workspaces?"
        )
        message = String.localizedStringWithFormat(format, groupName)
    } else {
        let format = String(
            localized: "dialog.deleteGroup.message.many",
            defaultValue: "Delete the group \u{201C}%1$@\u{201D} and close its %2$lld workspaces?"
        )
        message = String.localizedStringWithFormat(format, groupName, memberCount)
    }
    let alert = NSAlert()
    alert.messageText = title
    if let message {
        alert.informativeText = message
    }
    alert.alertStyle = .warning
    alert.addButton(
        withTitle: String(
            localized: "dialog.deleteGroup.confirm",
            defaultValue: "Delete"
        )
    )
    alert.addButton(
        withTitle: String(localized: "common.cancel", defaultValue: "Cancel")
    )
    if let confirmButton = alert.buttons.first {
        confirmButton.keyEquivalent = "\r"
        confirmButton.keyEquivalentModifierMask = []
        alert.window.defaultButtonCell = confirmButton.cell as? NSButtonCell
        alert.window.initialFirstResponder = confirmButton
    }
    if let cancelButton = alert.buttons.dropFirst().first {
        cancelButton.keyEquivalent = "\u{1b}"
    }
    return alert.runCmuxModal() == .alertFirstButtonReturn
}

/// Confirm-then-delete for a group, matching the classic sidebar's Delete
/// Group: the alert shows the live member count, and only the workspaces the
/// user confirmed are closed. Used by JS sidebars, which cannot present the
/// alert themselves.
/// - Returns: Whether the group was deleted.
@MainActor
@discardableResult
func confirmAndDeleteWorkspaceGroup(groupId: UUID, tabManager: TabManager) -> Bool {
    guard let confirmation = tabManager.workspaceGrouping.deletionConfirmation(groupId: groupId) else {
        return false
    }
    let isPinned = tabManager.workspaceGroups.first(where: { $0.id == groupId })?.isPinned ?? false
    if isPinned || confirmation.containedWorkspaceCount > 0 {
        guard confirmDeleteWorkspaceGroup(
            groupName: confirmation.groupName,
            memberCount: confirmation.containedWorkspaceCount
        ) else {
            return false
        }
    }
    tabManager.deleteWorkspaceGroup(confirmed: confirmation)
    return true
}
