import Foundation

extension TabManager {
    /// Closes a socket/API-targeted workspace without an interactive veto.
    ///
    /// Closing a window's last workspace means closing the window. A remote-tmux
    /// mirror is detached from its local owner first so a socket close never maps
    /// to the explicit remote-session kill path.
    @discardableResult
    func closeWorkspaceNonInteractively(
        _ workspace: Workspace,
        recordHistory: Bool = true,
        allowPinned: Bool = false
    ) -> Bool {
        guard canCloseWorkspace(workspace, allowPinned: allowPinned),
              tabs.contains(where: { $0.id == workspace.id }) else { return false }
        guard tabs.count == 1 else {
            closeWorkspace(workspace, recordHistory: recordHistory)
            return !tabs.contains(where: { $0.id == workspace.id })
        }
        guard let appDelegate = AppDelegate.shared,
              let windowId = appDelegate.windowId(for: self) else { return false }
        if workspace.isRemoteTmuxMirror {
            appDelegate.remoteTmuxController.detachMirrorWorkspaceKeptOpenLocally(workspaceId: workspace.id)
        }
        guard appDelegate.closeMainWindow(windowId: windowId, recordHistory: recordHistory) else {
            return false
        }
        return true
    }
}

// MARK: - Agent workspace (fork addition)

extension TabManager {
    /// Makes `workspace` the always-on agent workspace (or clears it with nil): it can't be
    /// closed, it's pinned at the top, and closing its last terminal starts `command` again.
    /// Only one agent workspace per window; setting a new one clears the old one.
    func setAgentHome(_ workspace: Workspace, command: String?) {
        let trimmed = command?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (trimmed?.isEmpty == false) ? trimmed : nil
        if value != nil {
            for other in tabs where other.id != workspace.id && other.isAgentHome {
                other.agentHomeCommand = nil
            }
        }
        workspace.agentHomeCommand = value
        guard value != nil else { return }
        if !workspace.isPinned { setPinned(workspace, pinned: true) }
        if tabs.first?.id != workspace.id { moveTabToTop(workspace.id) }
    }

    /// Called whenever the workspace list changes: if the agent workspace was moved down
    /// (drag, move-top of another pinned workspace, ...), put it back at the top.
    func scheduleAgentHomeKeepOnTopIfNeeded(_ newTabs: [Workspace]) {
        guard !agentHomeKeepOnTopScheduled,
              let index = newTabs.firstIndex(where: \.isAgentHome), index != 0,
              newTabs[index].groupId == nil else { return }
        agentHomeKeepOnTopScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.agentHomeKeepOnTopScheduled = false
            guard let agent = self.tabs.first(where: \.isAgentHome),
                  agent.groupId == nil, self.tabs.first?.id != agent.id else { return }
            if !agent.isPinned { self.setPinned(agent, pinned: true) }
            self.moveTabToTop(agent.id)
        }
    }
}
