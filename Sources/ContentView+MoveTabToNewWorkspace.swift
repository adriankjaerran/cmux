import CmuxCommandPalette
import AppKit
import CmuxFoundation
import SwiftUI

extension ContentView {
    func appendMoveTabToNewWorkspaceCommandContribution(
        to contributions: inout [CommandPaletteCommandContribution],
        panelSubtitle: @escaping (CommandPaletteContextSnapshot) -> String
    ) {
        contributions.append(
            CommandPaletteCommandContribution(
                commandId: "palette.moveTabToNewWorkspace",
                title: { _ in String(localized: "command.moveTabToNewWorkspace.title", defaultValue: "Move Tab to New Workspace") },
                subtitle: panelSubtitle,
                keywords: ["move", "tab", "workspace", "detach", "sidebar", "surface"],
                when: { $0.bool(CommandPaletteContextKeys.hasFocusedPanel) },
                enablement: { $0.bool(CommandPaletteContextKeys.panelCanMoveToNewWorkspace) }
            )
        )
    }

    func moveFocusedPanelToNewWorkspace() -> Bool {
        guard let panelContext = focusedPanelContext else { return false }
        return AppDelegate.shared?.moveSurfaceToNewWorkspace(
            panelId: panelContext.panelId,
            focus: true,
            focusWindow: false
        ) != nil
    }
}
