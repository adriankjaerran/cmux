import CmuxSurfaceCatalogModel
import Foundation

/// The provider returned a pane that does not match the requested placement.
struct SurfaceMaterializationPlacementMismatch: LocalizedError {
    var errorDescription: String? { "The surface opened in an unexpected place." }
}

extension SurfaceProvider {
    /// Checks the provider receipt before it can become a catalog projection.
    func materializeValidated(
        _ resource: SurfaceResource,
        remoteView: SurfaceRemoteView?,
        at destination: SurfaceDestination,
        focus: Bool
    ) async throws -> SurfaceProjection {
        var projection = try await materialize(resource, remoteView: remoteView, at: destination, focus: focus)
        let expectedWorkspace = remoteView?.workspace.id
        if projection.remoteWorkspaceID == nil,
           let expectedWorkspace,
           resource.remoteWorkspace?.id == expectedWorkspace {
            projection.remoteWorkspaceID = expectedWorkspace
        }
        guard projection.resource == resource.id,
              projection.workspaceID == destination.workspaceID,
              expectedWorkspace == nil || projection.remoteWorkspaceID == expectedWorkspace else {
            discardMaterialization(projection)
            throw SurfaceMaterializationPlacementMismatch()
        }
        return projection
    }
}
