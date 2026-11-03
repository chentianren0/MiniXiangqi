import Foundation

/// The 记谱法 preference.
enum NotationStyle: String, CaseIterable {
    case traditional
    case wxf

    static let key = "notation.style"

    /// Chinese reads the traditional rendering, every other language WXF. Only
    /// a default, never a migration: it answers only where the key is absent.
    static func resolved(forInterfaceLanguage identifier: String?) -> NotationStyle {
        guard let identifier,
              Locale.Language(identifier: identifier).languageCode == .chinese
        else { return .wxf }
        return .traditional
    }

    /// `preferredLocalizations`, not `Locale.current`: what matters is the
    /// language the app is drawn in, not the user's region or first language.
    static var resolvedForInterfaceLanguage: NotationStyle {
        resolved(forInterfaceLanguage: Bundle.main.preferredLocalizations.first)
    }
}

/// A move in both notations at once, so a game on screen re-renders the moment
/// the 记谱法 preference changes.
struct MoveReading: Hashable {
    var traditional: String
    var wxf: String

    /// A placement move reads as its coordinate and a Jieqi move in its own
    /// rendering, the same in both: the 记谱法 preference does not apply to them.
    /// Only a game that conceals reads `after`.
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

    /// The resumed game and a History replay both read through this, so they
    /// read a sitting as it was played. Quadratic, since each placement is a
    /// walk from the start. Only a game that conceals asks for the position
    /// after each ply, so it asks for one more position than there are plies.
    static func line(for moves: [String], on game: GameKind,
                     placementAt: (Int) throws -> Placement) throws -> [MoveReading] {
        try moves.enumerated().map { ply, text in
            guard let move = Move(text: text, on: game.board) else {
                throw UnreadableStoredMove(ply: ply)
            }
            return MoveReading(of: move, in: try placementAt(ply),
                               after: game.conceals ? try placementAt(ply + 1) : nil)
        }
    }

    /// A stored line never legitimately holds one: every move was checked
    /// against the rules before it was saved or imported.
    struct UnreadableStoredMove: Error, CustomStringConvertible {
        var ply: Int
        var description: String { "the stored line holds no move at ply \(ply)" }
    }
}
