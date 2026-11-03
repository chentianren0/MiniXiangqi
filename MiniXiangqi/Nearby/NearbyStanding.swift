// What a networked game's board draws, asked of the core: the position and the
// legal moves after a line of moves, without holding the record.

import Foundation
import MiniXiangqiCore

nonisolated struct NearbyStanding: Sendable {
    var evaluation: Evaluation
    var legalMoves: [String]
}

nonisolated protocol NearbyPositions: Sendable {
    func standing(of game: GameKind, from start: String,
                  after moves: [String]) -> NearbyStanding?
}

/// `@unchecked Sendable` because the core's rules entries are callable from any
/// thread, which Swift cannot read off the handle.
nonisolated struct CoreNearbyPositions: NearbyPositions, @unchecked Sendable {
    private let core: OpaquePointer

    init(core: OpaquePointer) {
        self.core = core
    }

    func standing(of game: GameKind, from start: String,
                  after moves: [String]) -> NearbyStanding? {
        guard let evaluation = try? Core.evaluate(core, game, from: start, moves: moves),
              let legalMoves = try? Core.legalMoves(core, game, from: start, moves: moves)
        else { return nil }
        return NearbyStanding(evaluation: evaluation, legalMoves: legalMoves)
    }
}

extension Core {
    var nearbyPositions: CoreNearbyPositions { CoreNearbyPositions(core: handle) }
}
