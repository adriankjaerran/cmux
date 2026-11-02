import Foundation

/// One runnable palette command: identity, display strings, search keywords,
/// and the action executed when the command is activated.
public struct CommandPaletteCommand: Identifiable {
    /// Stable command identifier.
    public let id: String
    /// Tie-break rank; lower sorts first at equal score.
    public let rank: Int
    /// Display title.
    public let title: String
    /// Display subtitle.
    public let subtitle: String
    /// Optional keyboard-shortcut hint shown trailing the row.
    public let shortcutHint: String?
    /// Optional kind label (for example a switcher row's surface kind).
    public let kindLabel: String?
    /// Additional search keywords.
    public let keywords: [String]
    /// Whether activating the command dismisses the palette.
    public let dismissOnRun: Bool
    /// Unread count shown as a red badge on the row (0 hides it).
    public let badgeCount: Int
    /// Small fixed-width label left of the title (the sidebar folder name in
    /// the switcher). nil hides the column; "" keeps it blank for alignment.
    public let leadingLabel: String?
    /// Whether the kind label is a "running" activity note (drawn in the
    /// sidebar's run blue).
    public let kindLabelIsRunning: Bool
    /// The action executed on activation.
    public let action: () -> Void

    /// Creates a command.
    public init(
        id: String,
        rank: Int,
        title: String,
        subtitle: String,
        shortcutHint: String?,
        kindLabel: String?,
        keywords: [String],
        dismissOnRun: Bool,
        badgeCount: Int = 0,
        leadingLabel: String? = nil,
        kindLabelIsRunning: Bool = false,
        action: @escaping () -> Void
    ) {
        self.id = id
        self.rank = rank
        self.title = title
        self.subtitle = subtitle
        self.shortcutHint = shortcutHint
        self.kindLabel = kindLabel
        self.keywords = keywords
        self.dismissOnRun = dismissOnRun
        self.badgeCount = badgeCount
        self.leadingLabel = leadingLabel
        self.kindLabelIsRunning = kindLabelIsRunning
        self.action = action
    }

    /// Texts the search corpus indexes for this command.
    public var searchableTexts: [String] {
        [title, subtitle] + keywords
    }
}
