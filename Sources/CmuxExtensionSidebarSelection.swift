import AppKit
import CmuxFoundation
import CmuxSettings
import CmuxSettingsUI
import CmuxSidebarProviderKit
import Foundation

enum CmuxExtensionSidebarSelection {
    @MainActor
    private static var inMemoryTemplatePreview: (providerId: String, source: String)?

    // No "." in this key: ContentView and VerticalTabsSidebar read it through
    // @AppStorage, and SwiftUI re-evaluated every view holding a dotted
    // @AppStorage key when an unrelated key changed (#13930).
    static let defaultsKey = "cmuxExtensionSidebarProviderId"
    static let legacyDefaultsKey = "cmuxExtensionSidebar.providerId"
    /// Fork: the left sidebar is always a custom sidebar; `compact.js` is the
    /// default. The native workspace list, the Conversations sidebar, the
    /// hosted-extensions sidebar and the bundled example providers were
    /// removed (Phase 10), so stored ids pointing at them resolve here.
    static let defaultProviderId = personalDefaultProviderId

    /// Synchronous read of the experimental Extensions flag for the on-demand
    /// AppKit/static paths (the toggle menu, the command-palette builder, the
    /// extensions-browser opener) that have no `SettingsRuntime` in scope and
    /// run outside the SwiftUI update cycle.
    ///
    /// SwiftUI views bind reactively via `@LiveSetting(\.betaFeatures.extensions)`.
    /// This synchronous read resolves the same catalog key
    /// (`BetaFeaturesCatalogSection.extensions`) against `UserDefaults`, which is
    /// the same suite and key the store persists to, so the catalog stays the
    /// single definition of the key, decode, and default.
    static var isEnabled: Bool {
        // Read the single beta-features section, not the whole `SettingCatalog`.
        // Constructing the full catalog allocates ~20 sub-sections (including
        // `AutomationCatalogSection`/`SecretFileKey`) just to reach one flag;
        // doing that on the SwiftUI body's hot path turned the sidebar
        // re-render into a CPU catastrophe (issue #5970).
        let key = BetaFeaturesCatalogSection().extensions
        return Bool.decodeFromUserDefaults(UserDefaults.standard.object(forKey: key.userDefaultsKey)) ?? key.defaultValue
    }

    // MARK: - Custom sidebars (beta)

    /// Provider-id prefix for user/agent-authored custom sidebars. The
    /// suffix after the prefix is the sidebar's file base name.
    static let customSidebarProviderPrefix = "cmux.sidebar.custom."

    /// Synchronous read of the experimental custom-sidebars flag, mirroring
    /// ``isEnabled`` for the AppKit/static paths (the picker menu).
    static var customSidebarsEnabled: Bool {
        customSidebarsEnabled(defaults: .standard)
    }

    static func customSidebarsEnabled(defaults: UserDefaults) -> Bool {
        // `DisableCustomSidebars` (MDM): interpreted sidebars are user- or
        // agent-authored code that can dispatch `cmux(...)` commands.
        guard !ManagedDevicePolicy().isEnforced(.disableCustomSidebars) else { return false }
        // See ``isEnabled``: read only the beta-features section so a body-path
        // access does not allocate the entire `SettingCatalog` (issue #5970).
        let key = BetaFeaturesCatalogSection().customSidebars
        return Bool.decodeFromUserDefaults(defaults.object(forKey: key.userDefaultsKey)) ?? key.defaultValue
    }

    /// Directory custom sidebars are authored into.
    static var customSidebarsDirectory: URL {
        #if DEBUG
        if let override = customSidebarsDirectoryOverrideForTesting { return override }
        #endif
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/cmux/sidebars", isDirectory: true)
    }

    /// Fork: sidebars shipped inside the app (`Contents/Resources/sidebars`,
    /// copied from the repo's `Resources/sidebars` at build time). A file with
    /// the same name in ``customSidebarsDirectory`` overrides the bundled one.
    static var bundledSidebarsDirectory: URL? {
        #if DEBUG
        if customSidebarsDirectoryOverrideForTesting != nil { return nil }
        #endif
        return Bundle.main.resourceURL?.appendingPathComponent("sidebars", isDirectory: true)
    }

    /// Fork: the sidebar the app uses until the person picks another one.
    static let personalDefaultProviderId = customSidebarProviderPrefix + "compact"

    /// One provider descriptor per `<name>.swift`/`<name>.json` file in the
    /// sidebars directory (`.swift` preferred when both exist), titled by the
    /// file's base name.
    static var customSidebarDescriptors: [CmuxSidebarProviderDescriptor] {
        guard !ManagedDevicePolicy().isEnforced(.disableCustomSidebars) else { return [] }
        var entries = (try? FileManager.default.contentsOfDirectory(
            at: customSidebarsDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        if let bundled = bundledSidebarsDirectory {
            entries += (try? FileManager.default.contentsOfDirectory(
                at: bundled,
                includingPropertiesForKeys: nil
            )) ?? []
        }
        // Priority when several extensions share a base name: js > swift > json.
        func priority(_ ext: String?) -> Int {
            switch ext {
            case "js": return 3
            case "swift": return 2
            case "json": return 1
            default: return 0
            }
        }
        var extensionByName: [String: String] = [:]
        for url in entries {
            let ext = url.pathExtension.lowercased()
            guard priority(ext) > 0 else { continue }
            let name = url.deletingPathExtension().lastPathComponent
            if priority(extensionByName[name]) >= priority(ext) { continue }
            extensionByName[name] = ext
        }
        return extensionByName.keys.sorted().map { name in
            CmuxSidebarProviderDescriptor(
                id: customSidebarProviderPrefix + name,
                title: CmuxSidebarProviderLocalizedText(key: "sidebar.provider.custom.\(name)", defaultValue: name),
                subtitle: CmuxSidebarProviderLocalizedText(
                    key: "sidebar.provider.custom.subtitle",
                    defaultValue: String(localized: "sidebar.provider.custom.subtitle", defaultValue: "Custom sidebar")
                ),
                systemImageName: "wand.and.stars",
                isHostProvided: false
            )
        }
    }

    /// Resolves a custom-sidebar provider id to its backing file URL
    /// (`.swift` preferred), or `nil` if neither file exists.
    static func customSidebarFileURL(forProviderId providerId: String) -> URL? {
        if let url = customSidebarFileURL(forProviderId: providerId, sidebarsDirectory: customSidebarsDirectory) {
            return url
        }
        guard let bundled = bundledSidebarsDirectory else { return nil }
        return customSidebarFileURL(forProviderId: providerId, sidebarsDirectory: bundled)
    }

    static func customSidebarFileURL(forProviderId providerId: String, sidebarsDirectory: URL) -> URL? {
        guard providerId.hasPrefix(customSidebarProviderPrefix) else { return nil }
        let name = String(providerId.dropFirst(customSidebarProviderPrefix.count))
        guard isValidCustomSidebarFileBaseName(name) else { return nil }
        for ext in ["js", "swift", "json"] {
            let url = sidebarsDirectory.appendingPathComponent("\(name).\(ext)", isDirectory: false)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private static func isValidCustomSidebarFileBaseName(_ name: String) -> Bool {
        guard !name.isEmpty, name != ".", name != ".." else { return false }
        return name == (name as NSString).lastPathComponent
    }

    /// Descriptors offered in the switcher menu and command palette: one per
    /// custom sidebar file (user dir and bundle).
    static var descriptors: [CmuxSidebarProviderDescriptor] {
        customSidebarDescriptors
    }

    static func descriptor(for providerId: String) -> CmuxSidebarProviderDescriptor? {
        descriptors.first { $0.id == providerId }
    }

    /// Resolves the persisted selection to the custom sidebar that is
    /// rendered: the stored id when it names a custom sidebar whose file
    /// exists (or the in-memory template preview), otherwise
    /// ``defaultProviderId``. Stored ids of removed providers
    /// (`cmux.sidebar.default`, `cmux.sidebar.conversations`,
    /// `cmux.sidebar.extensions`, the example providers) land on compact.
    /// Cheap enough for the SwiftUI body: at most three `fileExists` probes
    /// per directory.
    @MainActor
    static func effectiveProviderId(_ persistedProviderId: String) -> String {
        guard persistedProviderId.hasPrefix(customSidebarProviderPrefix) else { return defaultProviderId }
        if inMemoryTemplatePreview?.providerId == persistedProviderId { return persistedProviderId }
        return customSidebarFileURL(forProviderId: persistedProviderId) == nil ? defaultProviderId : persistedProviderId
    }

    /// Rewrites a stored selection that points at a removed built-in
    /// provider to ``defaultProviderId``. Custom ids are left alone even if
    /// their file is missing right now (it may come back).
    static func normalizeRemovedProviderSelection(defaults: UserDefaults = .standard) {
        guard let providerId = defaults.string(forKey: defaultsKey),
              !providerId.hasPrefix(customSidebarProviderPrefix) else { return }
        defaults.set(defaultProviderId, forKey: defaultsKey)
    }

    static func localizedTitle(for descriptor: CmuxSidebarProviderDescriptor) -> String {
        localizedText(descriptor.title)
    }

    static func localizedText(_ text: CmuxSidebarProviderLocalizedText) -> String {
        NSLocalizedString(
            text.key,
            tableName: "Localizable",
            bundle: .main,
            value: text.defaultValue,
            comment: ""
        )
    }

    static func setProviderId(_ providerId: String, defaults: UserDefaults = .standard) {
        defaults.set(providerId, forKey: defaultsKey)
    }

    static func clearStaleTemplatePreviewSelection(defaults: UserDefaults = .standard) {
        guard let providerId = defaults.string(forKey: defaultsKey),
              providerId.hasPrefix(customSidebarProviderPrefix + ".cmux-preview-") else { return }
        defaults.removeObject(forKey: defaultsKey)
    }

    @MainActor
    static func setInMemoryTemplatePreview(providerId: String, source: String) {
        inMemoryTemplatePreview = (providerId, source)
    }

    @MainActor
    static func clearInMemoryTemplatePreview() {
        inMemoryTemplatePreview = nil
    }

    @MainActor
    static func inMemoryTemplatePreviewSource(for providerId: String) -> String? {
        guard inMemoryTemplatePreview?.providerId == providerId else { return nil }
        return inMemoryTemplatePreview?.source
    }

    /// Moves a selection saved under `legacyDefaultsKey` before #13930.
    /// A selection already stored under `defaultsKey` wins; the legacy key is removed.
    static func migrateLegacyDefaultsKeyIfNeeded(defaults: UserDefaults = .standard) {
        guard let legacyProviderId = defaults.object(forKey: legacyDefaultsKey) else { return }
        defaults.removeObject(forKey: legacyDefaultsKey)
        guard defaults.object(forKey: defaultsKey) == nil else { return }
        defaults.set(legacyProviderId, forKey: defaultsKey)
    }

    @MainActor
    static func browseTemplates() {
        guard customSidebarsEnabled else { return }
        AppDelegate.shared?.openPreferencesWindow(
            debugSource: "sidebar.browseTemplates",
            navigationTarget: .customSidebars
        )
        SettingsNavigationRequest.post(.customSidebars, anchorID: "setting:customSidebars:templates", highlight: true)
        CustomSidebarTemplateGalleryRequest.shared.request()
    }

    @MainActor
    static func showMenu(anchorView: NSView, event: NSEvent?) {
        // The right-click menu switches between custom sidebar files.
        let menu = NSMenu()
        let persistedProviderId = UserDefaults.standard.string(forKey: defaultsKey) ?? defaultProviderId
        let selectedProviderId = effectiveProviderId(persistedProviderId)
        for descriptor in descriptors {
            let item = NSMenuItem(
                title: localizedTitle(for: descriptor),
                action: #selector(CmuxExtensionSidebarMenuTarget.selectProvider(_:)),
                keyEquivalent: ""
            )
            item.representedObject = descriptor.id
            item.target = CmuxExtensionSidebarMenuTarget.shared
            item.state = selectedProviderId == descriptor.id ? .on : .off
            item.image = NSImage(systemSymbolName: descriptor.systemImageName, accessibilityDescription: nil)
            menu.addItem(item)
        }
        if customSidebarsEnabled {
            menu.addItem(.separator())
            let templatesItem = NSMenuItem(
                title: String(localized: "sidebar.menu.browseTemplates", defaultValue: "Browse Sidebar Templates…"),
                action: #selector(CmuxExtensionSidebarMenuTarget.browseTemplates),
                keyEquivalent: ""
            )
            templatesItem.target = CmuxExtensionSidebarMenuTarget.shared
            menu.addItem(templatesItem)
        }
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: anchorView.bounds.maxY + 2),
            in: anchorView
        )
    }
}

@MainActor
private final class CmuxExtensionSidebarMenuTarget: NSObject {
    static let shared = CmuxExtensionSidebarMenuTarget()

    @objc func selectProvider(_ sender: NSMenuItem) {
        guard let providerId = sender.representedObject as? String else { return }
        CmuxExtensionSidebarSelection.setProviderId(providerId)
    }

    @objc func browseTemplates() {
        CmuxExtensionSidebarSelection.browseTemplates()
    }
}
