import Foundation

/// The app's own URL scheme (`cmux://`, `cmux-dev-<tag>://`, …), used for
/// workspace links, `cmux://ssh` requests and in-app link handling.
///
/// Same resolution as `AuthEnvironment.callbackScheme`, kept local so these
/// features don't depend on the Cloud package:
/// 1. `CMUX_AUTH_CALLBACK_SCHEME` (trimmed, non-empty) wins. In Debug, a value
///    in `~/.config/cmux/dev-profiles/<tag>.env` or `~/.cmux-dev.env` wins over
///    the process environment.
/// 2. Debug: `cmux-dev-<sanitized CMUX_TAG>`, or `cmux-dev` untagged.
/// 3. Release: `cmux-nightly` / `cmux-rc` by bundle id, else `cmux`.
/// The URL types in Info.plist must keep registering the same scheme.
enum AppURLScheme {
    static var callbackScheme: String {
        callbackScheme(
            environment: runtimeEnvironment,
            bundleIdentifier: Bundle.main.bundleIdentifier
        )
    }

    static func callbackScheme(
        environment: [String: String],
        bundleIdentifier: String?
    ) -> String {
        #if DEBUG
        return callbackScheme(environment: environment, bundleIdentifier: bundleIdentifier, isDebugBuild: true)
        #else
        return callbackScheme(environment: environment, bundleIdentifier: bundleIdentifier, isDebugBuild: false)
        #endif
    }

    static func callbackScheme(
        environment: [String: String],
        bundleIdentifier: String?,
        isDebugBuild: Bool
    ) -> String {
        if let overridden = environment[overrideKey]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !overridden.isEmpty {
            return overridden
        }
        if isDebugBuild {
            if let tag = environment["CMUX_TAG"]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !tag.isEmpty,
               let schemeTag = sanitizedSchemeTag(tag) {
                return "cmux-dev-\(schemeTag)"
            }
            return "cmux-dev"
        }
        if bundleIdentifier == "com.cmuxterm.app.nightly" { return "cmux-nightly" }
        if bundleIdentifier == "com.cmuxterm.app.rc" { return "cmux-rc" }
        return "cmux"
    }

    static func sanitizedSchemeTag(_ rawTag: String) -> String? {
        let lowercased = rawTag.lowercased()
        var result = ""
        var previousWasHyphen = false
        for scalar in lowercased.unicodeScalars {
            let isAllowed = (scalar.value >= 97 && scalar.value <= 122)
                || (scalar.value >= 48 && scalar.value <= 57)
            if isAllowed {
                result.unicodeScalars.append(scalar)
                previousWasHyphen = false
            } else if !previousWasHyphen {
                result.append("-")
                previousWasHyphen = true
            }
        }
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return result.isEmpty ? nil : result
    }

    private static let overrideKey = "CMUX_AUTH_CALLBACK_SCHEME"

    private static var runtimeEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        #if DEBUG
        if let value = debugFileOverride(environment: environment) {
            environment[overrideKey] = value
        }
        #endif
        return environment
    }

    #if DEBUG
    private static func debugFileOverride(environment: [String: String]) -> String? {
        guard let home = environment["HOME"] else { return nil }
        var paths: [String] = []
        if let tag = environment["CMUX_TAG"],
           tag.range(of: #"^[A-Za-z0-9._-]+\z"#, options: .regularExpression) != nil {
            paths.append((home as NSString).appendingPathComponent(".config/cmux/dev-profiles/\(tag).env"))
        }
        paths.append((home as NSString).appendingPathComponent(".cmux-dev.env"))
        for path in paths {
            guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            if let value = parseOverride(contents: contents) { return value }
        }
        return nil
    }

    private static func parseOverride(contents: String) -> String? {
        for raw in contents.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let parsedKey = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            guard parsedKey == overrideKey else { continue }
            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
            if value.hasPrefix("'") && value.hasSuffix("'") { value = String(value.dropFirst().dropLast()) }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }
    #endif
}
