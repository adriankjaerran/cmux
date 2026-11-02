import CmuxSurfaceCatalogModel
import Foundation

extension SurfaceCatalog {
    /// Guest display discovery for a machine whose Displays are on screen. The
    /// guest helper starts a standby display on this request, so the first
    /// New Display hands over a running desktop.
    /// Returns false, starting nothing, when the machine is asleep or has no
    /// desktop. `completion` reports whether discovery produced a guest catalog,
    /// so a failed attempt can be retried rather than treated as done.
    func beginDisplayDiscovery(
        on machine: SurfaceMachineID,
        completion: @escaping @MainActor (Bool) -> Void = { _ in }
    ) -> Bool {
        // Guest displays came from the cmux-tui provider (gone in Phase 9.12 (E)).
        _ = (machine, completion)
        return false
    }

    /// Names a display for every client; an empty name restores "Display N".
    func renameDisplay(_ id: SurfaceResourceID, name: String) async throws {
        _ = name
        throw SurfaceCatalogError.noProvider(id.machine)
    }

    /// Creates a guest display and publishes it in the machine pool. Projection
    /// into a local workspace is intentionally separate: the guest resource
    /// must survive a missing or changing local destination.
    func createDisplay(on machine: SurfaceMachineID) async throws -> SurfaceResource {
        throw SurfaceCatalogError.noProvider(machine)
    }

    /// Creation and opening share the placement policy. The guest resource stays
    /// on its VM if the selected destination disappears during creation.
    func createDisplay(on machine: SurfaceMachineID, into destination: SurfaceDestination) async throws {
        guard Workspace.liveWorkspace(id: destination.workspaceID) != nil else {
            throw SurfaceCatalogError.destinationNotFound(destination.workspaceID.uuidString)
        }
        let identity = SurfaceResourceID(machine: machine, kind: .display, key: "new")
        try validateOwnership(of: [identity], at: destination)
        try await createDisplayInReservedPane(on: machine, at: destination, bestEffortOpen: false)
    }

    /// Creates a display even when the selected workspace is unavailable. If
    /// the destination remains live, the new display is opened there; otherwise
    /// it stays available in the machine's Displays pool.
    func createDisplay(on machine: SurfaceMachineID, into destination: SurfaceDestination?) async throws {
        guard let destination, Workspace.liveWorkspace(id: destination.workspaceID) != nil,
              (try? validateOwnership(of: [SurfaceResourceID(machine: machine, kind: .display, key: "new")], at: destination)) != nil else {
            _ = try await createDisplay(on: machine)
            return
        }
        try await createDisplayInReservedPane(on: machine, at: destination, bestEffortOpen: true)
    }

    /// Opens the pane at the click, showing "Starting display…", then creates the
    /// guest display (a VM round trip) and binds that same pane to it. Creation
    /// failure closes the pane and throws. When opening the created display fails,
    /// the pane closes and the display stays in the machine's pool; that failure
    /// throws only when `bestEffortOpen` is false.
    private func createDisplayInReservedPane(
        on machine: SurfaceMachineID,
        at destination: SurfaceDestination,
        bestEffortOpen: Bool
    ) async throws {
        _ = (destination, bestEffortOpen)
        throw SurfaceCatalogError.noProvider(machine)
    }

}
