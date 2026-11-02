import CmuxSurfaceCatalogModel
import Foundation

/// Keeps a socket create and its requested native projection in one local intent.
extension TerminalController {
    nonisolated static func surfaceNewTerminal(
        machine: SurfaceMachineID,
        command: [String]?,
        cwd: String?,
        name: String?,
        remoteWorkspaceID: String?,
        destination: SurfaceDestination?,
        focus: Bool
    ) async throws -> [String: Any] {
        let catalog = await SurfaceCatalog.shared
        guard let provider = try await Self.surfaceProvider(for: machine, catalog: catalog) else {
            throw SurfaceCatalogError.noProvider(machine)
        }
        let resource = try await provider.createTerminal(command: command, cwd: cwd, name: name, remoteWorkspaceID: remoteWorkspaceID)
        var payload: [String: Any] = [
            "resource": resource.id.rawValue,
            "terminal_id": resource.id.key,
            "machine": machine.rawValue,
            "remote_workspace_id": resource.remoteWorkspace?.id ?? NSNull(),
        ]
        if let remoteWorkspaceName = resource.remoteWorkspace?.name,
           !remoteWorkspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["remote_workspace_name"] = remoteWorkspaceName
        }
        if let destination {
            let opened = try await catalog.project(
                resource.id,
                into: destination,
                focus: focus,
                reuseExisting: false,
                remoteView: nil
            )
            payload["workspace_id"] = opened.projection.workspaceID.uuidString
            payload["surface_id"] = opened.projection.panelID.uuidString
        }
        return payload
    }
}
