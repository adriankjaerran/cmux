import AppKit
import Foundation
import SwiftUI

/// One key press handed to a JS sidebar in keyboard mode.
public struct SidebarKeyPress: Equatable, Sendable {
    /// "up", "down", "left", "right", "return", "space", "escape", "tab",
    /// "delete", or the typed character (lowercased).
    public var key: String
    public var shift: Bool
    public var command: Bool
    public var option: Bool
    public var control: Bool

    public init(key: String, shift: Bool = false, command: Bool = false, option: Bool = false, control: Bool = false) {
        self.key = key
        self.shift = shift
        self.command = command
        self.option = option
        self.control = control
    }

    /// Maps an AppKit key-down to the JS key vocabulary, or nil for keys
    /// with no name (function keys, bare modifiers).
    public init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let name: String
        switch event.keyCode {
        case 126: name = "up"
        case 125: name = "down"
        case 123: name = "left"
        case 124: name = "right"
        case 36, 76: name = "return"
        case 49: name = "space"
        case 53: name = "escape"
        case 48: name = "tab"
        case 51, 117: name = "delete"
        default:
            guard let chars = event.charactersIgnoringModifiers?.lowercased(),
                  chars.count == 1,
                  let scalar = chars.unicodeScalars.first,
                  !CharacterSet.controlCharacters.contains(scalar),
                  // Arrow/function keys arrive as private-use scalars.
                  !(0xF700...0xF8FF).contains(scalar.value) else {
                return nil
            }
            name = chars
        }
        self.init(
            key: name,
            shift: flags.contains(.shift),
            command: flags.contains(.command),
            option: flags.contains(.option),
            control: flags.contains(.control)
        )
    }
}

/// What a JS sidebar's `onKey` handler decided.
public struct SidebarKeyResult: Equatable, Sendable {
    /// The key was consumed.
    public var handled: Bool
    /// Leave keyboard mode.
    public var exit: Bool
    /// Leave keyboard mode, select this workspace id and focus its terminal.
    public var openWorkspaceId: String?
    /// Ask to close this workspace id (the host confirms first).
    public var closeWorkspaceId: String?

    public init(handled: Bool, exit: Bool = false, openWorkspaceId: String? = nil, closeWorkspaceId: String? = nil) {
        self.handled = handled
        self.exit = exit
        self.openWorkspaceId = openWorkspaceId
        self.closeWorkspaceId = closeWorkspaceId
    }

    public static let unhandled = SidebarKeyResult(handled: false)

    /// Parses the runtime's `__key` reply.
    init(json: String) {
        guard let data = json.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            self = .unhandled
            return
        }
        self.init(
            handled: object["handled"] as? Bool ?? false,
            exit: object["exit"] as? Bool ?? false,
            openWorkspaceId: object["open"] as? String,
            closeWorkspaceId: object["close"] as? String
        )
    }
}

/// Window-scoped link from the app's keyboard routing to the JS sidebar
/// mounted in that window (sidebar keyboard mode).
///
/// The app owns one per window and injects it with
/// `.environment(\.customSidebarKeyboard, channel)`; the in-process JS host
/// attaches its engine while mounted. The out-of-process renderer never
/// attaches, so ``acceptsKeys`` stays false there.
@MainActor
public final class CustomSidebarKeyboardChannel {
    weak var engine: JSSidebarEngine?
    weak var anchorView: NSView?

    nonisolated public init() {}

    /// A mounted JS sidebar with an `onKey` handler is listening.
    public var acceptsKeys: Bool { engine?.handlesKeys ?? false }

    /// Turns the sidebar's `keyboardMode()` on or off (the cursor ring).
    public func setKeyboardMode(_ active: Bool) {
        engine?.setKeyboardMode(active)
    }

    /// Hands one key press to the sidebar.
    public func send(_ key: SidebarKeyPress) -> SidebarKeyResult {
        engine?.dispatchKey(key) ?? .unhandled
    }

    /// Whether a window-coordinate point falls in the sidebar's column
    /// (its horizontal extent; rows end above the bottom of the column).
    public func columnContains(windowPoint: NSPoint) -> Bool {
        guard let view = anchorView, view.window != nil else { return false }
        let frame = view.convert(view.bounds, to: nil)
        return windowPoint.x >= frame.minX && windowPoint.x <= frame.maxX
    }
}

private struct CustomSidebarKeyboardKey: EnvironmentKey {
    static let defaultValue: CustomSidebarKeyboardChannel? = nil
}

public extension EnvironmentValues {
    /// The window's sidebar keyboard channel, if the host offers one.
    var customSidebarKeyboard: CustomSidebarKeyboardChannel? {
        get { self[CustomSidebarKeyboardKey.self] }
        set { self[CustomSidebarKeyboardKey.self] = newValue }
    }
}

/// Click-through AppKit marker drawn behind the JS sidebar so the channel can
/// locate the sidebar column in window coordinates.
struct CustomSidebarKeyboardAnchor: NSViewRepresentable {
    let channel: CustomSidebarKeyboardChannel

    func makeNSView(context: Context) -> NSView {
        let view = PassThroughView()
        channel.anchorView = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        channel.anchorView = nsView
    }

    private final class PassThroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
