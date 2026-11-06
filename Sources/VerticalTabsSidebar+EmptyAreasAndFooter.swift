import AppKit
import CmuxAppKitSupportUI
import CmuxFoundation
import CmuxSettingsUI
import CmuxSidebar
import CmuxSidebarProviderKit
import CmuxWorkspaces
import SwiftUI

/// Footer controls for the left sidebar, extracted from `ContentView.swift`.
struct SidebarFooterIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SidebarFooterIconButtonStyleBody(configuration: configuration)
    }
}

struct SidebarFooterCircularIconStyle: Equatable {
    static let standard = SidebarFooterCircularIconStyle(
        pointSize: 14,
        weight: .regular
    )

    let pointSize: CGFloat
    let weight: Font.Weight

    func resized(to pointSize: CGFloat) -> SidebarFooterCircularIconStyle {
        SidebarFooterCircularIconStyle(pointSize: pointSize, weight: weight)
    }
}

enum SidebarFooterButtonMetrics {
    static let buttonSize: CGFloat = 22
    static let helpIconSize = SidebarFooterCircularIconStyle.standard.pointSize
    static let hoverOpacity = 0.08
}

enum SidebarFooterControl: CaseIterable, Equatable {
    case help
    case shortcutDiscovery
    case extensions
    case update
}

enum SidebarFooterPresentationPolicy {
    static func isVisible(
        _ control: SidebarFooterControl,
        presentationMode: WorkspacePresentationModeSettings.Mode
    ) -> Bool {
        switch control {
        case .help, .shortcutDiscovery, .extensions, .update:
            return presentationMode != .minimal
        }
    }
}

#if DEBUG
enum SidebarFooterIconButtonDebugSettings {
    static let hoverOpacityKey = "debug.sidebarFooterIconButton.hoverOpacity"
    static let defaultHoverOpacity = SidebarFooterButtonMetrics.hoverOpacity
}

enum SidebarFooterHelpIconDebugWeight: String, CaseIterable, Identifiable {
    case regular
    case medium
    case semibold

    var id: String { rawValue }

    var fontWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        }
    }

    var displayName: String {
        switch self {
        case .regular:
            String(localized: "debug.sidebarFooterIconBalance.weight.regular", defaultValue: "Regular")
        case .medium:
            String(localized: "debug.sidebarFooterIconBalance.weight.medium", defaultValue: "Medium")
        case .semibold:
            String(localized: "debug.sidebarFooterIconBalance.weight.semibold", defaultValue: "Semibold")
        }
    }
}

enum SidebarFooterHelpIconDebugChoice: String, CaseIterable, Identifiable {
    case bare = "questionmark"
    case circle = "questionmark.circle"
    case filledCircle = "questionmark.circle.fill"

    var id: String { rawValue }
}

enum SidebarFooterHelpIconDebugSettings {
    static let sizeKey = "debug.sidebarFooterHelpIcon.size"
    static let weightKey = "debug.sidebarFooterHelpIcon.weight"
    static let iconKey = "debug.sidebarFooterHelpIcon.symbol"
    static let defaultSize = Double(SidebarFooterButtonMetrics.helpIconSize)
    static let defaultWeight = SidebarFooterHelpIconDebugWeight.regular
    static let defaultIcon = SidebarFooterHelpIconDebugChoice.circle
}
#endif

struct SidebarFooterCircularIcon: View {
    let systemName: String
    let style: SidebarFooterCircularIconStyle
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.sidebarReadabilityBackdrop) private var readabilityBackdrop

    var body: some View {
        CmuxSystemSymbolImage(
            systemName: systemName,
            pointSize: style.pointSize,
            weight: style.weight,
            tint: SidebarAppearanceColorResolver().readableSecondary(for: colorScheme, over: readabilityBackdrop)
        )
    }
}

struct SidebarFooterHelpIcon: View {
    let style: SidebarFooterCircularIconStyle
#if DEBUG
    @AppStorage(SidebarFooterHelpIconDebugSettings.iconKey)
    private var debugIcon = SidebarFooterHelpIconDebugSettings.defaultIcon.rawValue
#endif

    init(pointSize: CGFloat, weight: Font.Weight) {
        style = SidebarFooterCircularIconStyle(pointSize: pointSize, weight: weight)
    }

    private var systemName: String {
#if DEBUG
        SidebarFooterHelpIconDebugChoice(rawValue: debugIcon)?.rawValue
            ?? SidebarFooterHelpIconDebugSettings.defaultIcon.rawValue
#else
        "questionmark.circle"
#endif
    }

    var body: some View {
        SidebarFooterCircularIcon(systemName: systemName, style: style)
    }
}

private struct SidebarFooterIconButtonStyleBody: View {
    let configuration: SidebarFooterIconButtonStyle.Configuration

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
#if DEBUG
    @AppStorage(SidebarFooterIconButtonDebugSettings.hoverOpacityKey)
    private var debugHoverOpacity = SidebarFooterIconButtonDebugSettings.defaultHoverOpacity
#endif

    private var hoverOpacity: Double {
#if DEBUG
        debugHoverOpacity
#else
        SidebarFooterButtonMetrics.hoverOpacity
#endif
    }

    private var backgroundOpacity: Double {
        guard isEnabled else { return 0.0 }
        if configuration.isPressed { return 0.16 }
        if isHovered { return hoverOpacity }
        return 0.0
    }

    var body: some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(backgroundOpacity))
            )
            .onHover { hovering in
                isHovered = hovering
            }
            .chromeRevealAnimation(isVisible: isHovered, fadeOut: .easeOut(duration: 0.12))
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

#if DEBUG
struct SidebarDevFooter: View {
    @ObservedObject var fileExplorerState: FileExplorerState
    let modifierKeyMonitor: WindowScopedShortcutHintModifierMonitor
    @AppStorage(DevBuildBannerDebugSettings.sidebarBannerVisibleKey)
    private var showSidebarDevBuildBanner = DevBuildBannerDebugSettings.defaultShowSidebarBanner

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SidebarFooterButtons(fileExplorerState: fileExplorerState, modifierKeyMonitor: modifierKeyMonitor)
            if showSidebarDevBuildBanner {
                Text(String(localized: "debug.devBuildBanner.title", defaultValue: "THIS IS A DEV BUILD"))
                    .cmuxFont(size: 11, weight: .semibold)
                    .foregroundColor(.red)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 10)
        .padding(.bottom, 6)
    }
}
#endif
