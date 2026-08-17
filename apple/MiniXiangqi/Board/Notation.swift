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
    /// Computed at each read rather than stored, because that is the shape every
    /// preference read in this app has and there is no reason for this one to be
    /// the exception. Caching would be perfectly sound — the language cannot
    /// change without a relaunch — and would save a locale lookup that nothing
    /// here is waiting on.
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
    /// placement — and the placement it produced, which only a game that
    /// conceals has anything to read from.
    ///
    /// **A placement move reads as its coordinate, in both.** The 记谱法
    /// preference selects between two ways of writing a xiangqi move, and these
    /// games have one convention of their own: the point the stone went on,
    /// spelled exactly as the board's own edges spell it. So the preference is
    /// inert here rather than being consulted and ignored — both readings are
    /// the same string, and whichever the list is drawn in, it draws that.
    ///
    /// **A Jieqi move reads in its own designed rendering, in both**, for the
    /// same reason in the other direction: docs/interaction-design.md's notation
    /// section says that game's move list does not follow the preference, the
    /// two readings it selects between being conventions this game has none of.
    /// `JieqiNotation` is the reading and carries its own reasons.
    init(of move: Move, in placement: Placement, after: Placement? = nil) {
        guard move.from != nil else {
            traditional = move.to.name
            wxf = move.to.name
            return
        }
        guard !placement.game.conceals else {
            let text = JieqiNotation.text(for: move, in: placement, after: after)
            traditional = text
            wxf = text
            return
        }
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
    ///
    /// Each ply is read from the position before it and the position after it,
    /// which is the position before the next one — so the walk asks for one
    /// more position than there are plies, and the last of them is where the
    /// game stands.
    static func line(for moves: [String], on board: BoardDefinition,
                     placementAt: (Int) throws -> Placement) throws -> [MoveReading] {
        try moves.enumerated().map { ply, text in
            guard let move = Move(text: text, on: board) else {
                throw UnreadableStoredMove(ply: ply)
            }
            return MoveReading(of: move, in: try placementAt(ply),
                               after: try placementAt(ply + 1))
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
