import Foundation

/// Saved state of an iOS Simulator pane. The Simulator pane was removed from
/// this fork; the type stays so session files that still contain one decode.
struct SessionSimulatorPanelSnapshot: Codable, Sendable {
    var deviceUDID: String?
    var runtimeIdentifier: String?
    var deviceTypeIdentifier: String?
}
