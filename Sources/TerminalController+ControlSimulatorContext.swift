import CmuxControlSocket
import Foundation

/// The iOS Simulator pane was removed from this fork. The control socket still
/// routes `simulator.*` commands here, and every one reports "unavailable".
extension TerminalController: ControlSimulatorContext {
    func controlSimulatorBeginType(
        routing: ControlRoutingSelectors,
        text: String
    ) -> ControlSimulatorTypeStartResolution {
        .inputUnavailable
    }

    func controlSimulatorBeginWebInspectorTargets(
        routing: ControlRoutingSelectors
    ) -> ControlSimulatorWebInspectorStartResolution {
        .unavailable
    }

    func controlSimulatorBeginWebInspectorAttach(
        routing: ControlRoutingSelectors,
        targetID: String
    ) -> ControlSimulatorWebInspectorStartResolution {
        .unavailable
    }

    func controlSimulatorBeginWebInspectorSend(
        routing: ControlRoutingSelectors,
        json: String
    ) -> ControlSimulatorWebInspectorStartResolution {
        .unavailable
    }

    func controlSimulatorBeginWebInspectorHighlight(
        routing: ControlRoutingSelectors,
        enabled: Bool
    ) -> ControlSimulatorWebInspectorStartResolution {
        .unavailable
    }

    func controlSimulatorBeginWebInspectorRelease(
        routing: ControlRoutingSelectors
    ) -> ControlSimulatorWebInspectorStartResolution {
        .unavailable
    }

    func controlSimulatorBeginOperation(
        routing: ControlRoutingSelectors,
        operation: ControlSimulatorOperation
    ) -> ControlSimulatorOperationStartResolution {
        .unavailable("Simulator panes are not available in this build")
    }
}
