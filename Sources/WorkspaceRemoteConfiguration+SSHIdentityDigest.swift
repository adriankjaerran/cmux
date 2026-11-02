import CmuxCore
import CmuxFoundation
import CryptoKit
import Foundation

extension WorkspaceRemoteConfiguration {
    /// The stable SSH endpoint identity that keys the per-machine clipboard-write
    /// trust (`SSHClipboardWriteTrustStore`). Same inputs and hash as upstream's
    /// `SSHTuiConnection.identityDigest`, so stored trust decisions keep matching.
    var sshIdentityDigest: String {
        let resolver = SSHAgentSocketResolver(environment: [:])
        let persistentOptions = sshOptions.filter {
            let key = resolver.optionKey($0) ?? ""
            return !["controlmaster", "controlpersist", "controlpath"].contains(key)
        }
        var components = [destination, port.map(String.init) ?? "", identityFile ?? ""] + persistentOptions
        if let routeIdentifier = routeSensitiveIdentifier {
            components.append(routeIdentifier)
        } else if routeSensitivity == .unidentified {
            components.append(SSHConnectionSharingOptions.unidentifiedRouteSensitiveMarkerOption)
        }
        return SHA256.hash(data: Data(components.joined(separator: "\0").utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}
