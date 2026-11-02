import Foundation
import Observation

/// Transient presentation owned by one Cloud surface, separate from team selection.
@MainActor
@Observable
final class CloudTeamPickerPresentation {
    var isPresented = false
    /// The Invite popover anchored to the header Invite button.
    var isInvitePresented = false
    /// The last failed switch or create, shown under the header until
    /// dismissed or the menu opens again.
    var teamChangeError: String?
}
