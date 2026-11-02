import AppKit
import CmuxCommandPalette
import CmuxSettings
import Foundation

extension CommandPaletteCommandContribution {
    static var newSimulatorPane: Self {
        Self(
            commandId: "palette.newSimulatorPane",
            title: { _ in
                String(localized: "command.newSimulatorPane.title", defaultValue: "New Simulator Pane")
            },
            subtitle: { _ in
                String(localized: "command.newSimulatorPane.subtitle", defaultValue: "iPhone and iPad")
            },
            keywords: ["new", "simulator", "iphone", "ipad", "ios", "pane"]
        )
    }
}

extension CommandPaletteHandlerRegistry {
    /// The iOS Simulator pane was removed from this fork; ContentView still
    /// registers this hook, so it is a no-op.
    @MainActor
    mutating func registerNewSimulatorPane(tabManager: TabManager, windowId: UUID) {}
}

extension KeyboardShortcutSettings.Action {
    static let simulatorActions: [Self] = [
        .simulatorHome,
        .simulatorRotateLeft,
        .simulatorRotateRight,
        .simulatorToggleAppearance,
        .simulatorToggleSoftwareKeyboard,
    ]

    var simulatorLabel: String {
        switch self {
        case .simulatorHome:
            String(localized: "shortcut.simulatorHome.label", defaultValue: "Simulator: Home")
        case .simulatorRotateLeft:
            String(localized: "shortcut.simulatorRotateLeft.label", defaultValue: "Simulator: Rotate Left")
        case .simulatorRotateRight:
            String(localized: "shortcut.simulatorRotateRight.label", defaultValue: "Simulator: Rotate Right")
        case .simulatorToggleAppearance:
            String(localized: "shortcut.simulatorToggleAppearance.label", defaultValue: "Simulator: Toggle Appearance")
        case .simulatorToggleSoftwareKeyboard:
            String(localized: "shortcut.simulatorToggleSoftwareKeyboard.label", defaultValue: "Simulator: Toggle Software Keyboard")
        default:
            preconditionFailure("Not a Simulator shortcut action")
        }
    }

    var simulatorDefaultShortcut: StoredShortcut {
        switch self {
        case .simulatorHome:
            StoredShortcut(key: "h", command: true, shift: true, option: false, control: false)
        case .simulatorRotateLeft:
            StoredShortcut(key: "←", command: true, shift: false, option: false, control: false)
        case .simulatorRotateRight:
            StoredShortcut(key: "→", command: true, shift: false, option: false, control: false)
        case .simulatorToggleAppearance:
            StoredShortcut(key: "a", command: true, shift: true, option: false, control: false)
        case .simulatorToggleSoftwareKeyboard:
            StoredShortcut(key: "k", command: true, shift: false, option: false, control: false)
        default:
            preconditionFailure("Not a Simulator shortcut action")
        }
    }
}
