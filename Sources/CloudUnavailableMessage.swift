import CmuxSettings
import Foundation

/// What a request that would need a Cloud machine answers. Cloud is gone from
/// this fork; the text is the one upstream showed when Cloud was turned off.
enum CloudUnavailableMessage {
    nonisolated static var text: String {
        if ManagedDevicePolicy().isEnforced(.disableCloud) { return ManagedCloudPolicy.disabledMessage }
        return String(localized: "cloud.feature.disabled", defaultValue: "Cloud Machines are temporarily unavailable.")
    }
}
