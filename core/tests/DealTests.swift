import MiniXiangqiCore
import Testing

/// Two devices playing one dealt game never send the deal: each derives it from
/// the seed, so every implementation of the derivation must produce these
/// starts byte for byte. The second seed was searched for because Red's third
/// draw lands in the rejection-sampling branch: an implementation that took
/// v mod n without discarding derives a different deal from it.
extension Core {
    @Suite struct Deal {
        @Test(arguments: [
            ("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
             "p~p~b~p~ka~c~n~c~/9/1p~5n~1/r~1p~1b~1r~1a~/9/9/R~1R~1N~1B~1C~/1N~5C~1/9/P~B~P~P~KP~A~P~A~ w - - 0 1"),
            ("1d3d520200000000000000000000000000000000000000000000000000000000",
             "b~a~p~r~kn~p~a~p~/9/1b~5c~1/r~1c~1p~1p~1n~/9/9/P~1C~1A~1R~1P~/1N~5B~1/9/N~P~A~P~KB~C~P~R~ w - - 0 1"),
        ])
        func theDerivationMatchesItsVectors(seed: String, startFEN: String) throws {
            var buffer = [CChar](repeating: 0, count: Int(MXQ_FEN_CAP))
            var length = 0
            var err = freshError()
            let status = mxq_rules_deal(MxqGameKind(MXQ_GAME_KIND_JIEQI), seed,
                                        &buffer, buffer.count, &length, &err)
            try #require(status == MXQ_OK, "\(describe(status, err))")
            #expect(string(buffer) == startFEN)
        }
    }
}
