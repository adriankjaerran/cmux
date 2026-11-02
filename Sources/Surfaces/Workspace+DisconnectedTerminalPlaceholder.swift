import AppKit
import Bonsplit
import CmuxSurfaceCatalogModel
import CmuxWorkspaces
import Foundation

@MainActor
extension Workspace {
    /// A saved relay-less SSH recovery terminal stays process-free: the pane is a
    /// manual-mirror terminal (no local command) with a "disconnected" overlay.
    func restoreDeviceDisplayPanel(_ snapshot: SessionPanelSnapshot, in pane: PaneID) -> UUID? {
        guard let panel = makeRemoteTmuxPanePanel(onInput: { _ in }, keyNameResolver: nil) else { return nil }
        panel.surface.setManualIONoReflow(false)
        panel.surface.onManualSizeApplied = { _ in }
        panel.surface.onRuntimeReady = {}
        panel.surface.onManualWindowAttached = {}
        panel.onTerminalFocus = {}
        guard let panelID = insertDisconnectedPlaceholderTab(panel, in: pane) else { return nil }
        let status = DeviceTerminalAttachmentStatus()
        panel.deviceAttachment = status
        status.onChange = { [weak self] in self?.postRemoteConnectionPresentationDidChange() }
        status.onRetry = {}
        status.update(connected: false, connecting: false)
        applySessionPanelMetadata(snapshot, toPanelId: panelID)
        return panelID
    }

    private static var disconnectedPlaceholderTabTitle: String {
        String(localized: "cloudTree.terminal.untitled", defaultValue: "terminal")
    }

    private func insertDisconnectedPlaceholderTab(_ panel: TerminalPanel, in pane: PaneID) -> UUID? {
        let previousPane = bonsplitController.focusedPaneId
        let previousTab = previousPane.flatMap { bonsplitController.selectedTab(inPane: $0)?.id }
        panels[panel.id] = panel
        panelTitles[panel.id] = Self.disconnectedPlaceholderTabTitle
        guard let tab = bonsplitController.createTab(
            title: Self.disconnectedPlaceholderTabTitle,
            icon: panel.displayIcon,
            iconAsset: nil,
            kind: SurfaceKind.terminal.rawValue,
            isDirty: panel.isDirty,
            isLoading: false,
            isPinned: false,
            inPane: pane
        ) else {
            panels.removeValue(forKey: panel.id)
            panel.close()
            return nil
        }
        bindSurface(tab, toPanelId: panel.id)
        rememberTerminalConfigInheritanceSource(panel)
        panel.surface.flushPendingManualSizeReportIfAttached()
        if let previousPane {
            bonsplitController.focusPane(previousPane)
            if let previousTab { bonsplitController.selectTab(previousTab) }
            panel.unfocus()
        }
        return panel.id
    }

    /// The live workspace with `id` in any window, or nil once it was retired.
    static func liveWorkspace(id: UUID) -> Workspace? {
        AppDelegate.shared?.tabManagerFor(tabId: id)?.tabs.first { $0.id == id }
    }
}
