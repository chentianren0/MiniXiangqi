// The two notations a player can read a game in, and the reading of a stored
// line that carries both.
//
// docs/interaction-design.md, "User-visible notation" and "WXF rendering": the
// move list renders in whichever notation the 记谱法 preference selects, and the
// board's numeral strips follow it. Both readings are presentation; the
// canonical `"<from><to>"` notation is what archives, fixtures, and the core
// interface store and exchange, whichever is selected.
//
// A game already on screen has to re-render the moment the preference changes,
// so a reading is not one string but both: the views select, and there is no
// moment at which one notation's list is a move ahead of the other's.

import Foundation

/// The 记谱法 preference. UserDefaults, standard domain, read at the moment of
/// use; absent — or anything unrecognized — means the default `resolved` below
/// names. The key is the interface between this and the Settings screen that
/// offers it.
enum NotationStyle: String, CaseIterable {
    case traditional
    case wxf

    static let key = "notation.style"

    /// The reading a launch shows where nobody has chosen one.
    ///
    /// **The default follows the interface language** — owner decision,
    /// 2026-07-30, recorded in issue #80 and amended into
    /// docs/interaction-design.md § User-visible notation. Chinese reads the
    /// traditional rendering, which is what Xiangqi instruction in Chinese
    /// actually uses; every other language reads WXF, which the contract
    /// introduces as the rendering "for a reader who has learned Xiangqi in the
    /// international notation rather than in Chinese" — and a reader of the
    /// English interface is that reader by definition.
    ///
    /// Stated as *Chinese, or else WXF* rather than as a pair, so a third
    /// localization would arrive with an answer already: a reader who is not
    /// reading Chinese is not reading a Chinese move list either.
    ///
    /// **This is a default and never a migration.** It answers only where the
    /// key is absent, so a player who has been in Settings keeps whatever they
    /// chose, including a choice that agrees with the other language's default.
    static func resolved(forInterfaceLanguage identifier: String?) -> NotationStyle {
        guard let identifier,
              Locale.Language(identifier: identifier).languageCode == .chinese
        else { return .wxf }
        return .traditional
    }

    /// The same, for the language this launch is actually drawn in.
    ///
    /// `Bundle.main.preferredLocalizations` and not `Locale.current`: the
    /// question is which words are on the screen, and that is the localization
    /// the bundle resolved from the system's preference list rather than the
    /// user's region or their first-choice language. A Chinese speaker whose
    /// phone is in English reads an English app, and an English move list is what
    /// matches it. The contract's own localization clause says the app follows
    /// the language the operating system selects *for it*, which is this list's
    /// definition.
    ///
    /// Read at the moment of use like every other preference. The language cannot
    /// change without a relaunch, so this is a constant in practice; it is not
    /// cached because nothing else here is, and a cached one would be one more
    /// thing to be wrong at launch.
    static var resolvedForInterfaceLanguage: NotationStyle {
        resolved(forInterfaceLanguage: Bundle.main.preferredLocalizations.first)
    }
}

/// A move as the player reads it, in both notations at once.
struct MoveReading: Hashable {
    var traditional: String
    var wxf: String

    /// The move as the player reads it, given the placement *before* it — which
    /// is what both readings are of, so they are taken together and from the one
    /// placement.
    init(of move: Move, in placement: Placement) {
        traditional = MoveNotation.text(for: move, in: placement)
        wxf = WXFNotation.text(for: move, in: placement)
    }

    func text(in style: NotationStyle) -> String {
        switch style {
        case .traditional: traditional
        case .wxf: wxf
        }
    }

    /// A stored line, read as it was written: each move's notation from the
    /// placement before it, which the core supplies ply by ply.
    ///
    /// This is the one way a recorded game becomes words, and both readers of a
    /// stored game go through it — the resumed active game and a History
    /// record's replay — so a relaunch and a replay read a sitting exactly as
    /// the sitting itself did. Quadratic in the line's length, because each
    /// placement is a walk from the start; a game's own length is the measure
    /// of what reading it is worth.
    static func line(for moves: [String],
                     placementBefore: (Int) throws -> Placement) throws -> [MoveReading] {
        try moves.enumerated().map { ply, text in
            guard let move = Move(text: text) else {
                throw UnreadableStoredMove(ply: ply)
            }
            return MoveReading(of: move, in: try placementBefore(ply))
        }
    }

    /// A stored move this app cannot read, which a stored line can never
    /// legitimately contain: the core validated the whole of it before any
    /// session over it existed.
    struct UnreadableStoredMove: Error, CustomStringConvertible {
        var ply: Int
        var description: String { "the stored line holds no move at ply \(ply)" }
    }
}
