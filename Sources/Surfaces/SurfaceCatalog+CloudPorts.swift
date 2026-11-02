import CmuxCloud
import CmuxFoundation
import CmuxSurfaceCatalogModel
import Foundation

extension SurfaceCatalog {
    /// Localized destination error shared by the sidebar and socket open paths.
    nonisolated static func portDestinationUnavailableMessage(machine: SurfaceMachineID) -> String {
        String(
            format: String(
                localized: "cloudTree.port.noLocalWorkspace",
                defaultValue: "No local workspace is showing %@; select a workspace and retry."
            ),
            machine.rawValue
        )
    }

    /// Localized explanation used by both the sidebar and socket port-open paths.
    nonisolated static func portPreviewUnavailableMessage(machineID: String) -> String {
        String(
            format: String(
                localized: "cloudTree.port.unsupported",
                defaultValue: "%@’s provider cannot open machine ports as previews; reach the service from inside the machine with `cmux vm exec %@ -- …`."
            ),
            machineID,
            machineID
        )
    }

    /// Opens one canonical cloud port through the catalog's provider and
    /// projection path.
    ///
    /// The resource is inserted when a caller names a port before the next
    /// discovery pass. Its identity is always `<machine>/browser/port:<n>`;
    /// refreshing the provider can therefore replace its metadata without
    /// changing the row, projection, or CLI address.
    @discardableResult
    func openCloudPort(
        machine: SurfaceMachineID,
        port: Int,
        into destination: SurfaceDestination,
        focus: Bool,
        reuseExisting: Bool,
        reuseInWorkspace: UUID? = nil
    ) async throws -> (projection: SurfaceProjection, reused: Bool) {
        let id = SurfaceResourceID(machine: machine, kind: .browser, key: SurfaceResourceID.portKey(port))
        try validateOwnership(of: [id], at: destination)
        guard machine.tuiMachineID != nil, (1...65_535).contains(port) else {
            throw SurfaceCatalogError.unsupported(
                String(localized: "cloudTree.port.invalidMachine", defaultValue: "Ports can only be opened on a cloud machine.")
            )
        }
        guard let provider = provider(for: machine) else {
            throw SurfaceCatalogError.noProvider(machine)
        }
        guard provider.supportsPortPreviews else {
            throw SurfaceCatalogError.unsupported(Self.portPreviewUnavailableMessage(machineID: machine.rawValue))
        }

        let directURL = provider.info.privateAddress.map {
            CmuxInternalHostnames().directPortURL(privateAddress: $0, port: port)
        }
        if var existing = resources[id] {
            // A machine address can be assigned after the first catalog pass.
            // Refresh the URL in place while preserving workspace/view metadata.
            if existing.port != port || existing.url != directURL {
                existing.port = port
                existing.url = directURL
                upsert(existing)
            }
        } else {
            upsert(CmuxTuiSnapshotParser.portBrowser(machine: machine, port: port, directURL: directURL))
        }
        return try await project(
            id,
            into: destination,
            focus: focus,
            reuseExisting: reuseExisting,
            reuseInWorkspace: reuseInWorkspace
        )
    }

    /// Chooses the local workspace that already shows the cloud machine's
    /// resources, falling back to the caller's captured workspace. When a
    /// resource carries remote-workspace membership, only sibling resources in
    /// those remote workspaces participate in the vote; this keeps a port from
    /// following an unrelated machine workspace.
    func preferredLocalWorkspaceID(
        for resourceID: SurfaceResourceID,
        fallback: UUID?
    ) -> UUID? {
        // Keep the lookup useful when a refresh retired the resource after a row
        // was rendered: a live projection still gives us an unambiguous owner.
        let resource = resources[resourceID]
        if let resource {
            return preferredLocalWorkspaceID(for: resource, fallback: fallback)
        }
        return projections.first(where: { $0.resource == resourceID })?.workspaceID ?? fallback
    }

    /// Resolves the local workspace for a value captured from a tree snapshot.
    /// Callers that begin an asynchronous open use this overload before yielding
    /// so a later catalog replacement cannot erase the remote-workspace context.
    func preferredLocalWorkspaceID(
        for resource: SurfaceResource,
        fallback: UUID?
    ) -> UUID? {
        let machine = resource.machine
        let remoteWorkspaceIDs = Set(resource.remoteWorkspaces.map(\.id))
        guard !remoteWorkspaceIDs.isEmpty else {
            // A machine-pool port has no remote workspace owner. Never infer one
            // from unrelated projections on the same machine.
            return projections.first(where: { $0.resource == resource.id })?.workspaceID ?? fallback
        }
        var relatedIDs = Set([resource.id])
        relatedIDs.formUnion(resources.values.compactMap { candidate -> SurfaceResourceID? in
            guard candidate.machine == machine else { return nil }
            return candidate.remoteWorkspaces.contains { remoteWorkspaceIDs.contains($0.id) }
                ? candidate.id
                : nil
        })

        var projectionCounts: [UUID: Int] = [:]
        for projection in projections where relatedIDs.contains(projection.resource) {
            projectionCounts[projection.workspaceID, default: 0] += 1
        }
        // Select the same highest-count/lowest-UUID winner as
        // `CloudTreeNodeBuilder.localWorkspaceShowing`, but in one pass. This
        // path runs for every port-row open, so sorting all local workspaces
        // needlessly turns a linear vote into O(W log W).
        var winner: (id: UUID, count: Int)?
        for (id, count) in projectionCounts {
            guard let current = winner else {
                winner = (id, count)
                continue
            }
            if count > current.count
                || (count == current.count && id.uuidString < current.id.uuidString) {
                winner = (id, count)
            }
        }
        return winner?.id ?? fallback
    }

    /// Keeps a port that was added or reopened while a provider refresh was
    /// suspended. `replaceResources` is intentionally authoritative for the
    /// provider snapshot, but it must not erase a just-started open (or a pane
    /// that is still live) between the scan and publication of that snapshot.
    func preservingConcurrentPortResources(
        _ refreshed: [SurfaceResource],
        on machine: SurfaceMachineID,
        since previous: [SurfaceResource]
    ) -> [SurfaceResource] {
        let refreshedIDs = Set(refreshed.map(\.id))
        let previousIDs = Set(previous.map(\.id))
        let projectedResourceIDs = Set(projections.map(\.resource))
        let displayPortsOwned = machineInfo(for: machine)?.hasDesktop == true
            || previous.contains { $0.kind == .display }
        var result = refreshed
        for candidate in snapshot.resources(on: machine)
        where candidate.id.isForwardedPort
            && !CmuxTuiSnapshotParser.internalPorts.contains(candidate.id.forwardedPort ?? -1)
            && (!displayPortsOwned || !CmuxTuiSnapshotParser.displayPorts.contains(candidate.id.forwardedPort ?? -1))
            && !refreshedIDs.contains(candidate.id) {
            let wasAddedDuringRefresh = !previousIDs.contains(candidate.id)
            let remainsProjected = projectedResourceIDs.contains(candidate.id)
            guard wasAddedDuringRefresh || remainsProjected else { continue }
            result.append(candidate)
        }
        return result
    }
}
