import AppKit

extension AppDelegate {
    func isMenuBackedShortcutAction(_ action: KeyboardShortcutSettings.Action) -> Bool {
        action != .showHideAllWindows
            && action != .globalSearch
            && action != .clearScreenKeepScrollback
            && action != .increaseWorkspaceTerminalFontSize
            && action != .decreaseWorkspaceTerminalFontSize
            && action != .resetWorkspaceTerminalFontSize
            && action != .fileExplorerOpenSelection
            && action != .fileExplorerOpenSelectionFinderAlias
    }
}
