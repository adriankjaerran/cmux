import CmuxSurfaceCatalogModel
import Foundation

extension SurfaceCatalog {
    /// Explicit catalog refreshes are user inventory requests, so they opt a
    /// machine into demand-driven port discovery without enabling background polls.
    func requestPortDiscovery(for machine: SurfaceMachineID) {
        // Port discovery ran in the cmux-tui provider (gone in Phase 9.12 (E)).
        _ = machine
    }

    /// User refresh includes the metadata needed to recover a missing private address.
    func refreshPortDiscovery(machine: SurfaceMachineID) async {
        _ = machine
    }
}
