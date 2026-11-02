import CMUXMobileCore
import CmuxFoundation
import CmuxTerminalCore
import Foundation

// Moved out of Sources/Mobile/MobileHostTerminalTheme.swift (Phase 9.14): the
// agent chat theme (AgentChatThemeSync) builds on it.

extension TerminalTheme {
    /// Builds the wire ``TerminalTheme`` from the Mac's resolved terminal config.
    ///
    /// `GhosttyConfig.loadForCmux()` already folds a named `theme = <name>`
    /// directive (any of Ghostty's bundled themes, e.g. `catppuccin-mocha`),
    /// Ghostty's built-in defaults or cmux's managed fresh-config appearance,
    /// and the user's explicit `background=`/`palette=` settings into concrete
    /// `NSColor`s, so reading those resolved colors here
    /// captures the *effective* palette for both custom configs and named ghostty
    /// themes. Any palette index the config did not populate falls back to the
    /// matching Monokai entry so the theme always has a complete 16-color
    /// palette.
    init(ghosttyConfig config: GhosttyConfig) {
        let monokai = TerminalTheme.monokai
        let palette: [String] = (0...15).map { index in
            config.palette[index]?.hexString() ?? monokai.palette[index]
        }
        // Only carry cursor-text when the Mac config actually parsed a
        // `cursor-text` directive. When it did not, `config.cursorTextColor` is
        // just a placeholder default that ghostty never applies (it derives
        // cursor-text contrast automatically), so forwarding it would make the
        // phone emit an explicit `cursor-text` line the Mac never had and mis-
        // color the cursor label. `nil` here lets the phone derive contrast too.
        let cursorColorSemantic = config.cursorColorSemantic.flatMap {
            TerminalTheme.CellRelativeColor(rawValue: $0.rawValue)
        }
        let cursorTextSemantic = config.cursorTextColorSemantic.flatMap {
            TerminalTheme.CellRelativeColor(rawValue: $0.rawValue)
        }
        let selectionBackgroundSemantic = config.selectionBackgroundSemantic.flatMap {
            TerminalTheme.CellRelativeColor(rawValue: $0.rawValue)
        }
        let selectionForegroundSemantic = config.selectionForegroundSemantic.flatMap {
            TerminalTheme.CellRelativeColor(rawValue: $0.rawValue)
        }
        let cursorText = config.hasParsedCursorTextColor && cursorTextSemantic == nil
            ? config.cursorTextColor.hexString()
            : nil
        self.init(
            background: config.backgroundColor.hexString(),
            foreground: config.foregroundColor.hexString(),
            boldColor: config.boldColor,
            cursor: config.cursorColor.hexString(),
            cursorColorSemantic: cursorColorSemantic,
            cursorText: cursorText,
            cursorTextSemantic: cursorTextSemantic,
            selectionBackground: config.selectionBackground.hexString(),
            selectionBackgroundSemantic: selectionBackgroundSemantic,
            selectionForeground: config.selectionForeground.hexString(),
            selectionForegroundSemantic: selectionForegroundSemantic,
            palette: palette
        )
    }
}
