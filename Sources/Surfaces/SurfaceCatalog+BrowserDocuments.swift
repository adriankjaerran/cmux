import CmuxSurfaceCatalogModel
import Foundation

extension SurfaceCatalog {
    struct CloudBrowserDocument {
        var url: URL
        var title: String
        var remoteTabID: String
        var revision: UInt64
    }

    /// WebKit owns a native Cloud browser's current document. Publishing it must
    /// neither navigate the daemon's separate browser nor scan/materialize panes.
    func cloudBrowserDocumentDidChange(_ browser: BrowserPanel) {
        // Cloud browser documents came from the cmux-tui provider (gone in Phase 9.12 (E)).
        _ = browser
    }

    /// The page a dropped Cloud browser row opens as a new daemon browser. A machine
    /// cannot place one tab twice, so a second view in a workspace mirrored to the
    /// same machine would be retired by reconciliation; the drop copies it instead.
    /// A viewer workspace without a mirrored remote workspace keeps the dragged tab itself.
    func cloudBrowserCopyURL(for group: SurfaceResourceGroup, intoWorkspace workspaceID: UUID) -> URL? {
        guard !group.representsWorkspace, group.placements.count == 1,
              let placement = group.placements.first else { return nil }
        let id = placement.resource
        guard id.machine.cloudMachineID != nil, id.kind == .browser, !id.isForwardedPort,
              cloudPlacementCoordinator.boundRemoteWorkspaceID(forLocalWorkspace: workspaceID, on: id.machine) != nil,
              let resource = resources[id], resource.remoteViews?.isEmpty == false else { return nil }
        // Copy the dragged view's page, not whichever view of this browser changed last.
        let draggedView = placement.remoteTabID.flatMap { tabID in resource.remoteViews?.filter { $0.tabID == tabID } }
        var dragged = resource
        if let draggedView, !draggedView.isEmpty { dragged.remoteViews = draggedView }
        let url = resourceWithCloudBrowserDocument(dragged).url.flatMap { URL(string: $0) }
        guard let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            return SurfacePaneFactory.blankURL
        }
        return url
    }

    func resourceWithCloudBrowserDocument(_ resource: SurfaceResource) -> SurfaceResource {
        guard resource.lifecycle != .unavailable,
              let documents = cloudBrowserDocuments[resource.id],
              let document = documents.values.filter({ document in
                  resource.remoteViews?.contains(where: { $0.tabID == document.remoteTabID }) == true
              }).max(by: { $0.revision < $1.revision }) else { return resource }
        var result = resource
        result.url = document.url.absoluteString
        result.detail = result.url
        result.title = document.title
        // The daemon names a newly created browser after its blank document.
        // That placeholder must not hide the native title; explicit names still win.
        result.remoteViews = resource.remoteViews?.map { view in
            var view = view
            if view.name?.trimmingCharacters(in: .whitespacesAndNewlines) == SurfacePaneFactory.blankURL.absoluteString {
                view.name = nil
            }
            return view
        }
        return result
    }
}
