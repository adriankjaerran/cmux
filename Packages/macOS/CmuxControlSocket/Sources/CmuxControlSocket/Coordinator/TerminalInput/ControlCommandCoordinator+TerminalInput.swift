internal import Foundation

/// The local terminal-input domain: `terminal.input` (main lane) and
/// `terminal.paste` (worker lane, asynchronous). The `mobile.terminal.*`
/// aliases stay in the mobile-host domain.
extension ControlCommandCoordinator {
    /// Dispatches the asynchronous terminal-input worker methods.
    ///
    /// - Parameters:
    ///   - request: The decoded request envelope.
    ///   - context: Live app seam passed explicitly from the worker lane.
    /// - Returns: The command result, or `nil` for other methods.
    public nonisolated func handleTerminalInputAsync(
        _ request: ControlRequest,
        context: (any ControlTerminalInputContext)?
    ) async -> ControlCallResult? {
        switch request.method {
        case "terminal.paste":
            return await context?.controlTerminalPaste(params: request.params)
        default:
            return nil
        }
    }

    /// Dispatches the synchronous terminal-input methods; returns `nil` for
    /// anything else so `handle(_:)` falls through to the next domain.
    ///
    /// - Parameter request: The decoded request envelope.
    /// - Returns: The command result, or `nil` if not a terminal-input method.
    func handleTerminalInput(_ request: ControlRequest) -> ControlCallResult? {
        switch request.method {
        case "terminal.input":
            return context?.controlTerminalInput(params: request.params)
        default:
            return nil
        }
    }
}
