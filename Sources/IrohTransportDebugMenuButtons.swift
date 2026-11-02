import SwiftUI

#if DEBUG
struct IrohAndAgentSessionDebugMenuButtons: View {
    let openReact: () -> Void
    let openSolid: () -> Void

    var body: some View {
        AgentSessionDebugMenuButtons(
            openReact: openReact,
            openSolid: openSolid
        )
        NotificationDebugMenuButtons()
    }
}

#endif
