import Bonsplit
import CmuxSurfaceCatalogModel
import CmuxWorkspaces
import Foundation
import GhosttyKit

extension Workspace {
    /// A one-tab edge drag leaves a placeholder behind. The moved surface owns
    /// its replacement's execution context, even though it is now in another pane.
    func repairDraggedTabPlaceholder(in originalPane: PaneID, movedTabPane: PaneID, orientation: SplitOrientation) {
        _ = movedTabPane
        _ = orientation
        repairLocalDraggedTabPlaceholder(in: originalPane, originalTabs: bonsplitController.tabs(inPane: originalPane))
    }

    /// Reuses the placeholder tab a one-tab edge drag leaves behind.
    private func repairLocalDraggedTabPlaceholder(in originalPane: PaneID, originalTabs: [Bonsplit.Tab]) {
        let controller = bonsplitController
        let placeholderTabs = originalTabs.filter { panelIdFromSurfaceId($0.id) == nil }
    #if DEBUG
        cmuxDebugLog(
            "split.placeholderRepair pane=\(originalPane.id.uuidString.prefix(5)) " +
            "action=reusePlaceholder placeholderCount=\(placeholderTabs.count)"
        )
    #endif
        if let replacementTab = placeholderTabs.first {
            // Keep the existing placeholder tab identity and replace only the panel mapping.
            // This avoids an extra create+close tab churn that can transiently render an
            // empty pane during drag-to-split of a single-tab pane.
            let inheritedConfig = inheritedTerminalConfig(inPane: originalPane)

            let replacementPanel = TerminalPanel(
                workspaceId: id,
                context: GHOSTTY_SURFACE_CONTEXT_SPLIT,
                configTemplate: inheritedConfig,
                portOrdinal: portOrdinal,
                additionalEnvironment: startupEnvironmentMergingWorkspaceEnvironment([:])
            )
            configureNewTerminalPanel(replacementPanel)
            panels[replacementPanel.id] = replacementPanel
            panelTitles[replacementPanel.id] = replacementPanel.displayTitle
            bindSurface(replacementTab.id, toPanelId: replacementPanel.id)

            bonsplitController.updateTab(
                replacementTab.id,
                title: replacementPanel.displayTitle,
                icon: .some(replacementPanel.displayIcon),
                iconImageData: .some(nil),
                kind: .some(SurfaceKind.terminal.rawValue),
                hasCustomTitle: false,
                isDirty: replacementPanel.isDirty,
                showsNotificationBadge: false,
                isLoading: false,
                isPinned: false
            )
            rememberTerminalConfigInheritanceSource(replacementPanel)
            publishCmuxSurfaceCreated(replacementPanel.id, paneId: originalPane, kind: "terminal", origin: "placeholder_repair", focused: false)

            for extraPlaceholder in placeholderTabs.dropFirst() {
                bonsplitController.closeTab(extraPlaceholder.id)
            }
        } else {
    #if DEBUG
            cmuxDebugLog(
                "split.placeholderRepair pane=\(originalPane.id.uuidString.prefix(5)) " +
                "fallback=createTerminalAndDropPlaceholders"
            )
    #endif
            _ = newTerminalSurface(inPane: originalPane, focus: false)
            for tab in controller.tabs(inPane: originalPane) {
                if panelIdFromSurfaceId(tab.id) == nil {
                    bonsplitController.closeTab(tab.id)
                }
            }
        }
    }
}
