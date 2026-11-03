import Foundation

extension SurfaceProjection {
    /// Desktop and port previews created on this Mac have no daemon tab.
    /// (Moved from CmuxCloud in Phase 9.15.)
    public var isLocalWorkspaceView: Bool {
        remoteTabID == nil && (resource.kind == .display || resource.isForwardedPort)
    }
}
