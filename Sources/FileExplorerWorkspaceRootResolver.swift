import CmuxSettings
import CmuxSurfaceCatalogModel
import Foundation

/// Both Files presentations resolve through the same workspace authority.
@MainActor
struct FileExplorerWorkspaceRootResolver {
    let catalog: SurfaceCatalog

    init(catalog: SurfaceCatalog? = nil) {
        self.catalog = catalog ?? SurfaceCatalog.shared
    }

    func resolve(_ workspace: Workspace) -> FileExplorerWorkspaceRoot {
        // A legacy `ssh:` binding keeps using its SSH transport, otherwise Files
        // would silently change hosts. Any other (Cloud) binding has no root.
        if let binding = workspace.cloudVMBinding {
            let vmID = binding.vmID
            if vmID.hasPrefix("ssh:") {
                guard let configuration = workspace.remoteConfiguration,
                      configuration.transport == .ssh else { return .none }
                return .remoteSSH(
                    workspaceId: workspace.id,
                    connection: SSHFileExplorerConnection(destination: configuration.destination,
                        port: configuration.port, identityFile: configuration.identityFile, sshOptions: configuration.fileOperationSSHOptions),
                    displayTarget: configuration.displayTarget,
                    rootPath: workspace.trustedRemoteCurrentDirectory,
                    isAvailable: workspace.remoteConnectionState == .connected,
                    unavailableDetail: workspace.remoteConnectionDetail ?? workspace.remoteDaemonStatus.detail
                )
            }
            // Cloud is gone from this fork: a Cloud binding has no Files root.
            return .none
        }
        if workspace.usesRemoteDirectoryProvenance {
            // A projection without an unambiguous workspace owner never becomes local or SSH.
            if !workspace.cloudBindingState.projectedResources.isEmpty ||
                catalog.projectionRecords(forWorkspace: workspace.id).contains(where: { !$0.resource.machine.isLocal }) {
                return .none
            }
            guard let configuration = workspace.remoteConfiguration,
                  configuration.transport == .ssh else { return .none }
            return .remoteSSH(
                workspaceId: workspace.id,
                connection: SSHFileExplorerConnection(destination: configuration.destination,
                    port: configuration.port, identityFile: configuration.identityFile, sshOptions: configuration.fileOperationSSHOptions),
                displayTarget: configuration.displayTarget,
                rootPath: workspace.trustedRemoteCurrentDirectory,
                isAvailable: workspace.remoteConnectionState == .connected,
                unavailableDetail: workspace.remoteConnectionDetail ?? workspace.remoteDaemonStatus.detail
            )
        }
        let path = workspace.currentDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        // A local workspace may not have reported a cwd yet (fresh and
        // restored workspaces do this briefly).  Files still belongs to this
        // Mac; use its home directory instead of dropping the root entirely.
        let localPath = path.isEmpty ? FileManager.default.homeDirectoryForCurrentUser.path : path
        return .local(workspaceId: workspace.id, path: localPath)
    }
}
