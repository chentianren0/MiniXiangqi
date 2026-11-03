import Foundation
import MiniXiangqiCore
import Testing

/// The engine thread and the configurations it searches under, through mxq.h.
extension Core {
    @Suite struct EngineThread {
        static let miniStart = "rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1"

        /// Switching variants re-runs the engine's network selection over the
        /// list the previous configuration left. A switch that did not would
        /// search the new board with the old network and say nothing, so each
        /// preparation must pass the bridge's check of what the engine loaded,
        /// and each search must come from that network's profile.
        @Test func aVariantSwitchWithoutATeardownSearchesTheNewNetwork() throws {
            try withCore { core throws in
                let steps: [(Int, [String], String)] = [
                    (MXQ_GAME_KIND_XIANGQI, ["b3e3", "b8e8"], "-xiangqi-c07e94a5c7cb"),
                    (MXQ_GAME_KIND_MINI_XIANGQI, ["b1b3", "f7f5"], "-minixiangqiaxf-ad52b8658c9e"),
                    (MXQ_GAME_KIND_XIANGQI, ["h3e3"], "-xiangqi-c07e94a5c7cb"),
                ]
                for (game, line, network) in steps {
                    let (status, detail) = prepare(core, game)
                    try #require(status == MXQ_OK, "\(detail)")
                    let result = try searched(core, game, line)
                    #expect(result.outcome == MXQ_SEARCH_MOVE)
                    #expect(string(of: result.profile_id).hasSuffix(network), "\(string(of: result.profile_id))")
                    let legal = try legalMoves(core, game, startFEN(game), line)
                    #expect(legal.contains(string(of: result.move.text)))
                }
            }
        }

        /// The right bytes under a name that does not begin with the variant's
        /// identifier: the engine silently turns NNUE off, and the bridge's
        /// check of the effective state is what refuses it.
        @Test func aNetworkUnderTheWrongBasenameRefuses() throws {
            let directory = try scratchAssets(["minixiangqi-variants.ini"])
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.copyItem(at: assets.appending(path: "minixiangqiaxf-ad52b8658c9e.nnue"),
                                             to: directory.appending(path: "minixiangqi-ad52b8658c9e.nnue"))
            try withCore(assets: directory) { core throws in
                let (status, detail) = prepare(core, MXQ_GAME_KIND_MINI_XIANGQI)
                #expect(status == MXQ_ERR_ENGINE_ASSET_MISMATCH, "\(detail)")
                #expect(try engineQuery(core).state == MXQ_ENGINE_STATE_UNINITIALIZED)
            }
        }

        /// A teardown after the other variant leaves the rules answering on the
        /// app's own board, and the app's variant prepares and searches again.
        @Test func aTeardownReturnsTheBridgeToTheAppVariant() throws {
            try withCore { core throws in
                try #require(prepare(core, MXQ_GAME_KIND_XIANGQI).0 == MXQ_OK)
                try #require(mxq_engine_teardown(core, nil) == MXQ_OK)
                let start = evaluate(core, MXQ_GAME_KIND_MINI_XIANGQI, Self.miniStart, [])
                #expect(start.status == MXQ_OK && start.state.state == MXQ_GAME_ONGOING)
                #expect(try legalMoves(core, MXQ_GAME_KIND_MINI_XIANGQI, Self.miniStart).count == 19)

                try #require(prepare(core, MXQ_GAME_KIND_MINI_XIANGQI).0 == MXQ_OK)
                let result = try searched(core, MXQ_GAME_KIND_MINI_XIANGQI, [])
                #expect(result.outcome == MXQ_SEARCH_MOVE)
                #expect(try legalMoves(core, MXQ_GAME_KIND_MINI_XIANGQI, Self.miniStart).contains(string(of: result.move.text)))
            }
        }

        @Test func shutdownDuringASearchCancelsAndJoins() throws {
            let core = try makeCore()
            try #require(prepare(core, MXQ_GAME_KIND_MINI_XIANGQI).0 == MXQ_OK)
            let delivery = Delivery()
            _ = try search(core, MXQ_GAME_KIND_MINI_XIANGQI, ["b1b3"], movetime: deep, delivery)

            let begun = ContinuousClock.now
            #expect(mxq_core_shutdown(core, nil) == MXQ_OK)
            #expect(ContinuousClock.now - begun < .milliseconds(Int(deep) / 2))
            #expect(delivery.called, "the callback fired before the join")
            #expect(delivery.outcome == MXQ_SEARCH_CANCELLED)
        }

        @Test func reconfigurationIsRefusedDuringASearch() throws {
            try withCore { core throws in
                try #require(prepare(core, MXQ_GAME_KIND_MINI_XIANGQI).0 == MXQ_OK)
                let delivery = Delivery()
                let ticket = try search(core, MXQ_GAME_KIND_MINI_XIANGQI, ["b1b3"], movetime: deep, delivery)

                #expect(prepare(core, MXQ_GAME_KIND_MINI_XIANGQI).0 == MXQ_ERR_STATE_SEARCH_IN_PROGRESS)
                #expect(prepare(core, MXQ_GAME_KIND_GOMOKU_15).0 == MXQ_ERR_STATE_SEARCH_IN_PROGRESS)
                #expect(mxq_engine_teardown(core, nil) == MXQ_ERR_STATE_SEARCH_IN_PROGRESS)
                #expect(mxq_search_cancel(core, ticket, nil) == MXQ_OK)
                _ = delivery.wait()
                #expect(mxq_engine_teardown(core, nil) == MXQ_OK)

                var next: UInt64 = 0
                let start = startFEN(MXQ_GAME_KIND_MINI_XIANGQI)
                #expect(mxq_search_start(core, MxqGameKind(MXQ_GAME_KIND_MINI_XIANGQI), start, nil, 0,
                                         deep, nil, nil, &next, nil) == MXQ_ERR_STATE_ENGINE_NOT_READY)
            }
        }

        @Test func cancelAllQuiescesTheEngineThread() throws {
            try withCore { core throws in
                try #require(prepare(core, MXQ_GAME_KIND_MINI_XIANGQI).0 == MXQ_OK)
                let delivery = Delivery()
                _ = try search(core, MXQ_GAME_KIND_MINI_XIANGQI, ["b1b3"], movetime: deep, delivery)

                #expect(mxq_core_cancel_all(core, nil) == MXQ_OK)
                #expect(delivery.called, "the callback fired before cancel-all returned")
                #expect(delivery.outcome == MXQ_SEARCH_CANCELLED)
                #expect(try engineQuery(core).state == MXQ_ENGINE_STATE_READY)
            }
        }

        @Test func noMoveOnATerminalPositionFailsCleanly() throws {
            try withCore { core throws in
                try #require(prepare(core, MXQ_GAME_KIND_MINI_XIANGQI).0 == MXQ_OK)
                let mate = ["b1b3", "a6a5", "b3d3"]
                let start = startFEN(MXQ_GAME_KIND_MINI_XIANGQI)
                #expect(evaluate(core, MXQ_GAME_KIND_MINI_XIANGQI, start, mate).state.state == MXQ_GAME_RED_WINS)

                let result = try searched(core, MXQ_GAME_KIND_MINI_XIANGQI, mate)
                #expect(result.outcome == MXQ_SEARCH_FAILED)
                #expect(result.status == MXQ_ERR_ENGINE_NO_MOVE)
                #expect(try engineQuery(core).state == MXQ_ENGINE_STATE_READY)
            }
        }

        /// Freestyle and Renju share one Rapfi engine: each switch is a full
        /// reconfiguration, and each search is the new rule's.
        @Test func rapfisRulesSwitchSerialisesThroughOneEngine() throws {
            try withCore { core throws in
                let order: [(Int, String)] = [
                    (MXQ_GAME_KIND_GOMOKU_15, "-freestyle15-6bc0d1b0ff8e"),
                    (MXQ_GAME_KIND_RENJU, "-renju15-7ab8c974c30d"),
                    (MXQ_GAME_KIND_GOMOKU_15, "-freestyle15-6bc0d1b0ff8e"),
                ]
                for (game, network) in order {
                    let (status, detail) = prepare(core, game)
                    try #require(status == MXQ_OK, "\(detail)")
                    let result = try searched(core, game, ["h8", "h9", "i8"])
                    #expect(result.outcome == MXQ_SEARCH_MOVE)
                    #expect(string(of: result.profile_id).hasSuffix(network), "\(string(of: result.profile_id))")
                    let legal = try legalMoves(core, game, startFEN(game), ["h8", "h9", "i8"])
                    #expect(legal.contains(string(of: result.move.text)))
                }
            }
        }

        @Test func aRapfiSearchWithoutItsEngineIsRefused() throws {
            try withCore { core throws in
                func start() -> MxqStatus {
                    var ticket: UInt64 = 0
                    return withCStrings(["h8"]) { texts in
                        mxq_search_start(core, MxqGameKind(MXQ_GAME_KIND_GOMOKU_15), startFEN(MXQ_GAME_KIND_GOMOKU_15),
                                         texts, 1, fast, nil, nil, &ticket, nil)
                    }
                }
                #expect(start() == MXQ_ERR_STATE_ENGINE_NOT_READY)
                try #require(prepare(core, MXQ_GAME_KIND_MINI_XIANGQI).0 == MXQ_OK)
                #expect(start() == MXQ_ERR_STATE_ENGINE_NOT_READY, "the other engine being ready is not this game's")
            }
        }
    }
}
