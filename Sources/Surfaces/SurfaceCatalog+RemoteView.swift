import CmuxSurfaceCatalogModel
import Foundation

extension SurfaceCatalog {
    /// Resolves an explicit remote placement (`surface.project --remote-tab-id/--remote-workspace-id`).
    /// Local resources have no remote views, so this is nil unless a placement was requested.
    func remoteView(
        for id: SurfaceResourceID,
        tabID: String? = nil,
        workspaceID: String? = nil
    ) throws -> SurfaceRemoteView? {
        guard let resource = resources[id] else { throw SurfaceCatalogError.unknownResource(id) }
        guard let views = resource.remoteViews else {
            if tabID != nil || workspaceID != nil {
                throw SurfaceCatalogError.unavailable(id, reason: "remote placement data is unavailable")
            }
            return nil
        }
        if let tabID {
            let matches = views.filter { $0.tabID == tabID }
            guard matches.count == 1, let view = matches.first else {
                if matches.count > 1 {
                    throw SurfaceCatalogError.unavailable(id, reason: "remote tab \(tabID) has ambiguous placement")
                }
                throw SurfaceCatalogError.unavailable(id, reason: "remote tab \(tabID) is no longer present")
            }
            if let workspaceID, view.workspace.id != workspaceID {
                throw SurfaceCatalogError.unavailable(id, reason: "remote tab \(tabID) is not in workspace \(workspaceID)")
            }
            return view
        }
        guard let workspaceID else { return nil }
        let matches = views.filter { !$0.isCloudDisplayMembershipView && $0.workspace.id == workspaceID }
        guard matches.count <= 1 else {
            throw SurfaceCatalogError.ambiguousRemotePlacement(id, workspaceID: workspaceID)
        }
        guard let view = matches.first else {
            throw SurfaceCatalogError.unavailable(id, reason: "remote workspace \(workspaceID) has no view of this resource")
        }
        return view
    }
}
