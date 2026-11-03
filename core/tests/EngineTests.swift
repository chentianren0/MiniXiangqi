import Darwin
import Foundation
import MiniXiangqiCore
import Testing

/// Preparing and searching both engines through mxq.h, and the refusals that
/// stand between a damaged installation and a search.
extension Core {
    @Suite struct Engines {
        static let rulesFile = "minixiangqi-variants.ini"
        static let miniNetwork = "minixiangqiaxf-ad52b8658c9e.nnue"
        static let xiangqiNetwork = "xiangqi-c07e94a5c7cb.nnue"
        static let freestyleWeights = "mix9svqfreestyle_bsmix-6bc0d1b0ff8e.bin.lz4"
        static let renjuBlackWeights = "mix9svqrenju_bs15_black-7ab8c974c30d.bin.lz4"

        @Test func eachGamePreparesTheEngineItIsPlayedOn() throws {
            try withCore { core throws in
                func preparedProfile(_ game: Int) throws -> String {
                    let (status, detail) = prepare(core, game)
                    #expect(status == MXQ_OK, "\(detail)")
                    let query = try engineQuery(core)
                    #expect(query.state == MXQ_ENGINE_STATE_READY)
                    return query.profile
                }
                let gomoku = try preparedProfile(MXQ_GAME_KIND_GOMOKU_15)
                #expect(gomoku.hasSuffix("-freestyle15-6bc0d1b0ff8e"), "\(gomoku)")
                let renju = try preparedProfile(MXQ_GAME_KIND_RENJU)
                #expect(renju.hasSuffix("-renju15-7ab8c974c30d"), "\(renju)")
                let mini = try preparedProfile(MXQ_GAME_KIND_MINI_XIANGQI)
                #expect(mini.hasSuffix("-minixiangqiaxf-ad52b8658c9e"), "\(mini)")
                let xiangqi = try preparedProfile(MXQ_GAME_KIND_XIANGQI)
                #expect(xiangqi.hasSuffix("-xiangqi-c07e94a5c7cb"), "\(xiangqi)")
                #expect(try preparedProfile(MXQ_GAME_KIND_RENJU) == renju)

                #expect(mxq_engine_teardown(core, nil) == MXQ_OK)
                #expect(try engineQuery(core).state == MXQ_ENGINE_STATE_UNINITIALIZED)
            }
        }

        /// 256 MiB is the minimum table, and the reserve is the greater of a
        /// fifth of the probe or 128 MiB: 384 MiB available is exactly enough.
        @Test func aBudgetBelowTheMinimumConfiguresNothing() throws {
            try withCore { core throws in
                var budget = ampleBudget()
                budget.available_bytes = 383 << 20
                for game in [MXQ_GAME_KIND_GOMOKU_15, MXQ_GAME_KIND_MINI_XIANGQI] {
                    #expect(prepare(core, game, budget).0 == MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY)
                    #expect(try engineQuery(core).state == MXQ_ENGINE_STATE_UNINITIALIZED)
                }

                budget.available_bytes = 384 << 20
                var plan = MxqEnginePlan()
                plan.struct_size = UInt32(MemoryLayout<MxqEnginePlan>.size)
                #expect(mxq_engine_prepare(core, MxqGameKind(MXQ_GAME_KIND_MINI_XIANGQI), &budget, &plan, nil) == MXQ_OK)
                #expect(plan.hash_mib == 256)
            }
        }

        @Test func aMissingNetworkRefuses() throws {
            let assets = try scratchAssets([Self.rulesFile])
            defer { try? FileManager.default.removeItem(at: assets) }
            try withCore(assets: assets) { core throws in
                let (mini, miniDetail) = prepare(core, MXQ_GAME_KIND_MINI_XIANGQI)
                #expect(mini == MXQ_ERR_ENGINE_ASSET_MISSING, "\(miniDetail)")
                let (renju, renjuDetail) = prepare(core, MXQ_GAME_KIND_RENJU)
                #expect(renju == MXQ_ERR_ENGINE_ASSET_MISSING)
                #expect(renjuDetail.contains(Self.renjuBlackWeights), "\(renjuDetail)")
                #expect(try engineQuery(core).state == MXQ_ENGINE_STATE_UNINITIALIZED)
            }
        }

        /// With the hashes gone, a damaged file is caught by what the engine
        /// actually loaded: Fairy-Stockfish's effective network, Rapfi's
        /// effective evaluator.
        @Test func aTruncatedNetworkRefuses() throws {
            let assets = try scratchAssets([Self.rulesFile])
            defer { try? FileManager.default.removeItem(at: assets) }
            for name in [Self.miniNetwork, Self.freestyleWeights] {
                let bytes = try Data(contentsOf: Self.bundled(name))
                try bytes.prefix(bytes.count / 2).write(to: assets.appending(path: name))
            }
            try withCore(assets: assets) { core throws in
                let (mini, miniDetail) = prepare(core, MXQ_GAME_KIND_MINI_XIANGQI)
                #expect(mini == MXQ_ERR_ENGINE_ASSET_MISMATCH, "\(miniDetail)")
                let (gomoku, gomokuDetail) = prepare(core, MXQ_GAME_KIND_GOMOKU_15)
                #expect(gomoku != MXQ_OK, "\(gomokuDetail)")
                #expect(try engineQuery(core).state == MXQ_ENGINE_STATE_UNINITIALIZED)
            }
        }

        /// Real Renju weights under the freestyle name: Rapfi's evaluator maker
        /// swallows the mismatch and would leave classical evaluation, so the
        /// bridge's evaluator gate is what refuses it.
        @Test func weightsForAnotherRuleRefuse() throws {
            let assets = try scratchAssets([Self.rulesFile])
            defer { try? FileManager.default.removeItem(at: assets) }
            try FileManager.default.copyItem(at: Self.bundled(Self.renjuBlackWeights),
                                             to: assets.appending(path: Self.freestyleWeights))
            try withCore(assets: assets) { core throws in
                let (status, detail) = prepare(core, MXQ_GAME_KIND_GOMOKU_15)
                #expect(status == MXQ_ERR_ENGINE_ASSET_MISMATCH, "\(detail)")
                #expect(try engineQuery(core).state == MXQ_ENGINE_STATE_UNINITIALIZED)
            }
        }

        @Test(arguments: [
            (MXQ_GAME_KIND_MINI_XIANGQI, ["b1b3", "f7f5"]),
            (MXQ_GAME_KIND_XIANGQI, ["b3e3", "b8e8"]),
            (MXQ_GAME_KIND_GOMOKU_15, ["h8", "h9", "i8"]),
            (MXQ_GAME_KIND_RENJU, ["h8", "h9", "i8"]),
        ])
        func aSearchAnswersALegalMoveWithinItsThinkingTime(game: Int, line: [String]) throws {
            try withCore { core throws in
                let (status, detail) = prepare(core, game)
                try #require(status == MXQ_OK, "\(detail)")
                let begun = ContinuousClock.now
                let result = try searched(core, game, line)
                #expect(ContinuousClock.now - begun < .seconds(5))
                #expect(result.outcome == MXQ_SEARCH_MOVE, "\(statusName(result.status))")
                #expect(result.nodes > 0)
                let legal = try legalMoves(core, game, startFEN(game), line)
                #expect(legal.contains(string(of: result.move.text)), "\(string(of: result.move.text))")
            }
        }

        @Test func aCancelledSearchStopsEarly() throws {
            try withCore { core throws in
                try #require(prepare(core, MXQ_GAME_KIND_GOMOKU_15).0 == MXQ_OK)
                let line = ["h8", "h9", "i8"]
                let delivery = Delivery()
                let begun = ContinuousClock.now
                let ticket = try search(core, MXQ_GAME_KIND_GOMOKU_15, line, movetime: deep, delivery)
                Thread.sleep(forTimeInterval: 0.15)
                #expect(mxq_search_cancel(core, ticket, nil) == MXQ_OK)
                let result = try #require(delivery.wait())
                #expect(ContinuousClock.now - begun < .milliseconds(Int(deep) / 2))
                #expect(result.outcome == MXQ_SEARCH_CANCELLED)
                #expect(try searched(core, MXQ_GAME_KIND_GOMOKU_15, line).outcome == MXQ_SEARCH_MOVE,
                        "the engine searches again after a cancellation")
            }
        }

        /// A library must not write to its host's standard output, and both
        /// engines print by default.
        @Test func theEnginesWriteNothingToStandardOutput() throws {
            var pipe: [Int32] = [0, 0]
            try #require(Darwin.pipe(&pipe) == 0)
            fflush(stdout)
            let saved = dup(STDOUT_FILENO)
            dup2(pipe[1], STDOUT_FILENO)
            let outcome = Result {
                try withCore { core throws in
                    for (game, line) in [(MXQ_GAME_KIND_MINI_XIANGQI, ["b1b3"]), (MXQ_GAME_KIND_GOMOKU_15, ["h8"])] {
                        try #require(prepare(core, game).0 == MXQ_OK)
                        _ = try searched(core, game, line)
                    }
                }
            }
            fflush(stdout)
            dup2(saved, STDOUT_FILENO)
            close(saved)
            close(pipe[1])
            var buffer = [UInt8](repeating: 0, count: 4096)
            let count = read(pipe[0], &buffer, buffer.count)
            close(pipe[0])
            try outcome.get()
            #expect(count == 0, "\(String(decoding: buffer.prefix(max(count, 0)), as: UTF8.self))")
        }

        static func bundled(_ name: String) -> URL {
            MiniXiangqiCoreTests.assets.appending(path: name)
        }
    }
}
