import Foundation

/// Fork: the native workspace row that drew the compact status glyph was
/// removed (Phase 10). Only the `sidebar.compactStatusIcons` key names stay,
/// so an existing cmux.json still validates.
enum SidebarCompactStatusGlyph {
    /// The customizable states; raw values are the `sidebar.compactStatusIcons`
    /// keys in cmux.json.
    enum IconSlot: String, CaseIterable {
        case error
        case needsInput
        case subagents
        case running
        case waiting
        case starting
        case unseen
        case pullRequestOpen
        case pullRequestMerged
        case pullRequestClosed
        case idle
        case branch
        case terminal
    }
}
