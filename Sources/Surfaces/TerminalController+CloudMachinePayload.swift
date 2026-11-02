import CmuxSurfaceCatalogModel
import Foundation

extension TerminalController {
    nonisolated static func surfaceMachinePayload(_ info: SurfaceMachineInfo) -> [String: Any] {
        var presence: Any = NSNull()
        if let record = info.presence {
            presence = [
                "state": record.state.rawValue,
                "last_seen_at": record.lastSeenAt.map { $0.timeIntervalSince1970 } ?? NSNull(),
                "tag": record.tag,
                "bundle_id": record.bundleID ?? NSNull(),
                "account_trust": record.accountTrust.rawValue,
                "build_label": record.buildLabel ?? NSNull(),
            ] as [String: Any]
        }
        let kind: String
        switch info.id {
        case .local: kind = "local"
        case .cloud: kind = "cloud"
        case .ssh: kind = "ssh"
        case .device: kind = "device"
        }
        let linkErrorMessage: Any = {
            guard case .cloud = info.id, info.linkState != .connected else { return NSNull() }
            return info.linkFailureMessage
        }()
        return [
            "id": info.id.rawValue,
            "local": info.id.isLocal,
            "kind": kind,
            "presence": presence,
            "port_discovery_state": info.portDiscoveryState.wireValue,
            "name": info.name,
            "status": info.status,
            "image": info.image ?? NSNull(),
            "has_desktop": info.hasDesktop,
            "memory_mb": info.memoryMb ?? NSNull(),
            "cpus": info.cpus ?? NSNull(),
            "disk_mb": info.diskMb ?? NSNull(),
            "link_state": info.linkState.rawValue,
            "link_error": info.linkError ?? NSNull(),
            "link_error_message": linkErrorMessage,
            "cpu_percent": info.cpuPercent ?? NSNull(),
            "memory_used_mb": info.memoryUsedMb ?? NSNull(),
            "disk_used_mb": info.diskUsedMb ?? NSNull(),
            "remote_workspaces": info.remoteWorkspaces.map { $0.map(surfaceRemoteWorkspacePayload) } ?? NSNull(),
        ]
    }
}

extension SurfaceMachineInfo {
    /// Copy for a failed remote graph refresh (moved from the deleted cmux-tui provider,
    /// Phase 9.12 (E)). State-specific failures take precedence over diagnostics because a
    /// missing graph is not necessarily a network failure. Internal snake-case reason codes
    /// stay out of user-facing errors.
    var linkFailureMessage: String {
        let machineUnavailableMessage = String(
            localized: "cloud.operation.failure.machineUnavailable",
            defaultValue: "cmux cannot reach the Cloud service for this machine right now."
        )
        let networkMessage = String(
            localized: "cloud.operation.failure.network",
            defaultValue: "The Cloud connection did not complete. Check your connection and try again."
        )
        switch linkState {
        case .asleep:
            return String(localized: "cloud.operation.failure.machineAsleep", defaultValue: "This machine is asleep. Wake it to connect.")
        case .unavailable:
            return machineUnavailableMessage
        default:
            guard let linkError else { return networkMessage }
            let message = linkError.trimmingCharacters(in: .whitespacesAndNewlines)
            if message == "cloud_api_unavailable" {
                return machineUnavailableMessage
            }
            guard !message.isEmpty,
                  message.range(of: #"^[a-z][a-z0-9]*(?:_[a-z0-9]+)+$"#, options: .regularExpression) == nil else {
                return networkMessage
            }
            return message
        }
    }
}
