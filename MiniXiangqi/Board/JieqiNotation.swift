// Jieqi has no established notation, so its moves read in WXF's shape: letters
// and digits fit the move list's cell and read the same in either interface
// language. It ignores the 记谱法 preference.
//
// A face-down mover is named by the role its square gives it, marked `~`
// (`H~8+7`), because the move's geometry is written in that role and the role
// is public. The reveal follows a colon (`H~8+7:C`). A rendering may show only
// what the reading player is entitled to know.

import Foundation

enum JieqiNotation {

    /// The reveal is read from `after`, where the piece stands face up and its
    /// identity is public, never from the hidden piece in `before`.
    static func text(for move: Move, in before: Placement, after: Placement?) -> String {
        let text = WXFNotation.text(for: move, in: before)
        guard let revealed = reveal(of: move, in: before, after: after) else {
            return text
        }
        return text + ":" + WXFNotation.letter(revealed)
    }

    private static func reveal(of move: Move, in before: Placement,
                               after: Placement?) -> PieceKind? {
        guard let origin = move.from, before[origin]?.isFaceDown == true,
              let arrived = after?[move.to], !arrived.isFaceDown
        else { return nil }
        return arrived.kind
    }
}
