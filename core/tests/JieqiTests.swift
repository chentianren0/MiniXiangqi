import MiniXiangqiCore
import Testing

/// Fairy-Stockfish and the Pikafish slice both declare namespace Stockfish and
/// the same strong symbols; the slice is renamed so that each engine answers
/// from its own tables. These cases ask each engine a question only it answers
/// correctly, in one process.
extension Core {
    @Suite struct Jieqi {
        static let dealtStart = "p~c~p~n~kb~r~a~p~/9/1n~5r~1/a~1b~1c~1p~1p~/9/9/B~1A~1C~1P~1P~/1R~5N~1/9/P~N~P~R~KC~P~A~B~ w - - 0 1"

        @Test func eachEngineAnswersForItsOwnGame() throws {
            try withCore { core throws in
                let mini = startFEN(MXQ_GAME_KIND_MINI_XIANGQI)
                #expect(mini == "rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1")
                #expect(try legalMoves(core, MXQ_GAME_KIND_MINI_XIANGQI, mini).count == 19)
                #expect(try legalMoves(core, MXQ_GAME_KIND_JIEQI, Self.dealtStart).count == 44)

                var violation = MxqSetupViolation()
                violation.struct_size = UInt32(MemoryLayout<MxqSetupViolation>.size)
                var err = freshError()
                let status = mxq_rules_validate_setup(core, MxqGameKind(MXQ_GAME_KIND_JIEQI), Self.dealtStart, &violation, &err)
                #expect(status == MXQ_OK, "a dealt start is a position to set up in: \(describe(status, err))")
            }
        }

        /// A face-down piece moves as the piece whose square it stands on: the
        /// advisor on d1 has exactly the step to the palace centre.
        @Test func aFaceDownPieceMovesAsItsSquare() throws {
            try withCore { core throws in
                let moves = try legalMoves(core, MXQ_GAME_KIND_JIEQI, Self.dealtStart)
                #expect(moves.filter { $0.hasPrefix("d1") } == ["d1e2"])
            }
        }

        /// The slice's MAX_MOVES was 128, below Jieqi's derived maximum of 175,
        /// and a position past it wrote beyond the move list's storage.
        @Test func aPositionPastTheOldMoveCapacity() throws {
            try withCore { core throws in
                let fen = "3k5/9/3C5/6R2/5C3/2R6/9/1P~5P~1/4K4/P~7P~ w - - 0 1"
                var err = freshError()
                #expect(mxq_rules_validate_fen(core, MxqGameKind(MXQ_GAME_KIND_JIEQI), fen, &err) == MXQ_OK)
                let count = try legalMoves(core, MXQ_GAME_KIND_JIEQI, fen).count
                #expect(count > 128 && count <= 175, "\(count) legal moves")
            }
        }

        /// Nothing searches Jieqi: there is nothing to prepare, no network to
        /// name, no profile, no frozen start, and no hint for a session of it.
        @Test func nothingSearchesJieqi() throws {
            try withCore { core throws in
                var buffer = [CChar](repeating: 0, count: Int(MXQ_PROFILE_ID_CAP))
                var length = 0
                #expect(mxq_rules_start_fen(MxqGameKind(MXQ_GAME_KIND_JIEQI), &buffer, buffer.count, &length, nil) == MXQ_ERR_ARG_RANGE)
                #expect(mxq_engine_profile_id(MxqGameKind(MXQ_GAME_KIND_JIEQI), &buffer, buffer.count, &length, nil) == MXQ_ERR_ARG_RANGE)
                var profile = MxqGameProfile()
                profile.struct_size = UInt32(MemoryLayout<MxqGameProfile>.size)
                #expect(mxq_core_game_profile(MxqGameKind(MXQ_GAME_KIND_JIEQI), &profile, nil) == MXQ_ERR_ARG_RANGE)
                #expect(prepare(core, MXQ_GAME_KIND_JIEQI).0 == MXQ_ERR_ARG_RANGE)

                let game = try freePlay(core, MXQ_GAME_KIND_JIEQI, start: Self.dealtStart)
                defer { mxq_game_release(game) }
                var status = MxqGameStatus()
                status.struct_size = UInt32(MemoryLayout<MxqGameStatus>.size)
                #expect(mxq_game_status(game, &status, nil) == MXQ_OK)
                #expect(status.search_expected == 0)
                var ticket: UInt64 = 0
                #expect(mxq_search_start_hint(core, game, UInt32(MXQ_MOVETIME_FAST_MS), nil, nil, &ticket, nil)
                    == MXQ_ERR_STATE_ENGINE_NOT_READY)
            }
        }
    }
}

/// A Free Play session of `game`, the store's one active game.
func freePlay(_ core: OpaquePointer, _ game: Int, start: String = "") throws -> OpaquePointer {
    var config = MxqGameConfig()
    config.struct_size = UInt32(MemoryLayout<MxqGameConfig>.size)
    config.game = MxqGameKind(game)
    config.mode = MxqPlayMode(MXQ_PLAY_MODE_FREE_PLAY)
    config.human_side = MxqColor(MXQ_COLOR_NONE)
    config.ai_level = MxqAiLevel(MXQ_AI_LEVEL_NONE)
    config.first_mover_choice = MxqFirstMoverChoice(MXQ_FIRST_MOVER_NONE)
    config.local_side = MxqColor(MXQ_COLOR_NONE)
    withUnsafeMutableBytes(of: &config.start_fen) { buffer in
        let bytes = Array(start.utf8)
        buffer.copyBytes(from: bytes)
        buffer[bytes.count] = 0
    }
    var handle: OpaquePointer?
    var err = freshError()
    let status = mxq_game_create(core, &config, &handle, &err)
    try #require(status == MXQ_OK, "mxq_game_create: \(describe(status, err))")
    return try #require(handle)
}
