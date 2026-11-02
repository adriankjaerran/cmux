import Foundation
import CMUXMobileCore
import CmuxCloud

extension WorkspacePresenceScope {
    /// Resolves the host-owned scope used by Mac clients and Cloud projections.
    @MainActor static func forWorkspace(_ workspace: Workspace?) -> WorkspacePresenceScope? {
        guard let workspace else { return nil }
        // Cloud scopes needed the signed-in team (gone in Phase 9.13).
        if workspace.cloudVMBinding != nil { return nil }
        guard let ownerID = UUID(uuidString: MobileHostIdentity.deviceID()) else { return nil }
        return WorkspacePresenceScope(kind: .mac, ownerID: ownerID.uuidString, instanceTag: MobileHostIdentity.instanceTag(), workspaceID: workspace.id.uuidString)
    }
}
