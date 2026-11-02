import Foundation

/// Stub: the layout RPC host was served by the mobile host, which went with
/// `Sources/Mobile` (Phase 9.14). Only the names other Devices files read stay
/// until `Sources/Devices` goes.
enum DeviceWorkspaceLayoutHost {
    nonisolated static let eventTopic = "device.workspace.layout.changed"
    nonisolated static let externalGeometryKey = "deviceLayoutExternal"
    nonisolated static let layoutGeometryKey = "deviceLayoutSnapshot"
}
