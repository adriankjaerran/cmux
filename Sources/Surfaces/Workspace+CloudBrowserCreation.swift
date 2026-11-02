import AppKit
import CmuxCloud
import CmuxSurfaceCatalogModel
import Foundation

@MainActor
extension Workspace {
    struct CloudBrowserCreationRoute {
        let machine: SurfaceMachineID
        let remoteWorkspaceID: String?
        let screenID: String?
        let paneID: String?
        let url: URL
    }

    /// The value captured before a native browser placeholder is inserted.
    /// Both browser entrypoints use this plan so Cloud routing and unavailable
    /// handling cannot drift between split and tab creation.
    struct CloudBrowserCreationPlan {
        let route: CloudBrowserCreationRoute?
        let unavailable: Bool
        let unsupportedURL: Bool
        /// Session restore must not let WebKit load the saved URL before its
        /// Cloud resource is rebound to the machine provider.
        let suppressInitialNavigation: Bool
    }

    /// Resolves the remote target once for a browser creation intent. Restore
    /// uses the catalog's saved projection instead of issuing a new mutation.
    func cloudBrowserCreationPlan(
        sourcePanelID: UUID?,
        requestedURL: URL?,
        creationPolicy: BrowserPanelCreationPolicy
    ) -> CloudBrowserCreationPlan {
        let route = creationPolicy == .restoration
            ? nil
            : cloudBrowserCreationRoute(sourcePanelID: sourcePanelID, requestedURL: requestedURL)
        let requiresCloudBrowser = cloudVMBinding.map {
            SurfaceMachineID(rawValue: $0.vmID).cloudMachineID != nil
        } ?? false
        let unsupportedURL = requiresCloudBrowser && creationPolicy != .restoration &&
            requestedURL.map { !Self.cloudBrowserURLIsSupported($0) } == true
        return CloudBrowserCreationPlan(
            route: route,
            unavailable: creationPolicy != .restoration && requiresCloudBrowser && route == nil,
            unsupportedURL: unsupportedURL,
            suppressInitialNavigation: creationPolicy == .restoration && requiresCloudBrowser
        )
    }

    private static func cloudBrowserURLIsSupported(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "http", "https", "about": return true
        default: return false
        }
    }

    /// Returns a remote browser target only for a bound Cloud workspace. SSH
    /// workspaces continue through their existing browser path.
    func cloudBrowserCreationRoute(sourcePanelID: UUID?, requestedURL: URL?) -> CloudBrowserCreationRoute? {
        // Cloud browsers were created through the cmux-tui provider (gone in Phase 9.12 (E)).
        _ = (sourcePanelID, requestedURL)
        return nil
    }

    /// Applies the shared post-insertion action for split and tab entrypoints.
    func applyCloudBrowserCreationPlan(_ plan: CloudBrowserCreationPlan, to panel: BrowserPanel) {
        if plan.unsupportedURL {
            panel.cloudAccess.showUnavailable(String(
                localized: "cloud.portAccess.invalidURL",
                defaultValue: "This port does not have a valid HTTP or HTTPS address."
            ))
        } else if plan.unavailable {
            panel.cloudAccess.showUnavailable(String(
                localized: "cloud.browser.creationUnavailable",
                defaultValue: "Cloud browsers are unavailable on this machine. Refresh the machine and retry."
            ))
        }
    }

}
