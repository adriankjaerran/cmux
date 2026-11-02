internal import Foundation

/// The remaining bare `terminal.*` verbs of the former mobile-host domain
/// (`terminal.create`, `terminal.replay`, `terminal.viewport`,
/// `terminal.scroll`, `terminal.mouse`). The `mobile.*` aliases are gone with
/// the phone. Each method is a thin pass-through to its
/// ``ControlMobileHostContext`` seam method.
extension ControlCommandCoordinator {
    /// Dispatches the bare `terminal.*` verbs; returns `nil` for anything else
    /// so the core `handle(_:)` can fall through to the legacy dispatcher.
    ///
    /// - Parameter request: The decoded request envelope.
    /// - Returns: The command result, or `nil` if not one of these methods.
    func handleMobileHost(_ request: ControlRequest) -> ControlCallResult? {
        switch request.method {
        case "terminal.create":
            return context?.controlMobileTerminalCreate(params: request.params)
        case "terminal.replay":
            return context?.controlMobileTerminalReplay(params: request.params)
        case "terminal.viewport":
            return context?.controlMobileTerminalViewport(params: request.params)
        case "terminal.scroll":
            return context?.controlMobileTerminalScroll(params: request.params)
        case "terminal.mouse":
            return context?.controlMobileTerminalMouse(params: request.params)
        default:
            return nil
        }
    }
}
