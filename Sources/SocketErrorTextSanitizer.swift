import Foundation

/// Hides provider diagnostics, credentials, addresses and paths from socket error text.
enum SocketErrorTextSanitizer {
    nonisolated static var hiddenOutputPlaceholder: String {
        String(
            localized: "command.cloudVM.failed.details.hidden",
            defaultValue: "Additional technical details are available in logs."
        )
    }

    nonisolated static func sanitized(_ output: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let lowercased = trimmed.lowercased()
        let normalized = lowercased
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
        let blockedTerms = [
            "authorization",
            "aws_",
            "bearer",
            "billingcustomer",
            "billingteam",
            "cmux_vm_",
            "cookie",
            "credential",
            "database",
            "e2b",
            "freestyle",
            "http://",
            "https://",
            "itemid",
            "manifest",
            "migration",
            "postgres",
            "private key",
            "private_key",
            "provider",
            "rds",
            "refresh token",
            "refresh_token",
            "secret",
            "session id",
            "session_id",
            "snapshot",
            "stack auth",
            "token",
        ]
        let normalizedBlockedTerms = [
            "authorization",
            "aws",
            "bearer",
            "billingcustomer",
            "billingteam",
            "cmuxvmapi",
            "cookie",
            "credential",
            "database",
            "e2b",
            "freestyle",
            "itemid",
            "manifest",
            "migration",
            "postgres",
            "privatekey",
            "provider",
            "rds",
            "refreshtoken",
            "secret",
            "sessionid",
            "snapshot",
            "stackauth",
            "token",
        ]
        let containsBlockedTerm = blockedTerms.contains { lowercased.contains($0) }
            || normalizedBlockedTerms.contains { normalized.contains($0) }
        let containsLikelyEmail = trimmed.contains("@")
        let containsLikelyIPAddress = trimmed.range(
            of: #"(?<!\d)(?:\d{1,3}\.){3}\d{1,3}(?!\d)"#,
            options: .regularExpression
        ) != nil
        let containsLikelyFilesystemPath = trimmed.range(
            of: #"(^|[\s"'(\[])(~[/\w.-]*|/(Users|home|private|var/folders)/|/[^ \n\t"'()]+/[^ \n\t"'()]+)"#,
            options: .regularExpression
        ) != nil
        guard !containsBlockedTerm,
              !containsLikelyEmail,
              !containsLikelyIPAddress,
              !containsLikelyFilesystemPath else {
            return hiddenOutputPlaceholder
        }
        return trimmed
    }
}
