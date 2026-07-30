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
/// use; absent — or anything unrecognized — means the traditional reading, which
/// is the accepted default. The key is the interface between this and the
/// Settings screen that offers it.
enum NotationStyle: String, CaseIterable {
    case traditional
    case wxf

    static let key = "notation.style"
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
