import CmuxCommandPalette

// Computer Use was removed from this fork. ContentView still calls these
// hooks, so they stay as empty stubs.
extension ContentView {
    static let commandPaletteComputerUseOpenSetupCommandId = "palette.computerUse.openSetup"
    static let commandPaletteComputerUseAccessibilityCommandId = "palette.computerUse.accessibility"
    static let commandPaletteComputerUseScreenRecordingCommandId = "palette.computerUse.screenRecording"

    static func commandPaletteComputerUseContributions() -> [CommandPaletteCommandContribution] { [] }

    func registerComputerUseCommandPaletteHandlers(_ registry: inout CommandPaletteHandlerRegistry) {}
}
