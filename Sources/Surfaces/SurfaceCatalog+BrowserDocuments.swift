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

    /// The resource as panes and readers present it (browser rows carry their native document).
    func resourceForPresentation(_ resource: SurfaceResource) -> SurfaceResource {
        resource.kind == .browser ? resourceWithCloudBrowserDocument(resource) : resource
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
