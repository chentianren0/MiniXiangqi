import MiniXiangqiCore
import Testing

/// Two devices playing one dealt game never send the deal: each derives it from
/// the seed and the nonce, so every implementation of the derivation must
/// produce these values byte for byte. Both vectors take thirty-two zero bytes
/// as the seed. The second nonce was searched for because Red's seventh draw
/// lands in the rejection-sampling branch: an implementation that took v mod n
/// without discarding derives a different deal from it.
extension Core {
    @Suite struct Deal {
        @Test(arguments: [
            ("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
             "a~r~n~p~kb~b~c~a~/9/1p~5p~1/p~1p~1r~1n~1c~/9/9/A~1R~1B~1P~1N~/1N~5A~1/9/P~C~P~B~KC~P~R~P~ w - - 0 1",
             "ed1c9fb490c3d2f0e011e283c229b1408174109b7e632f8a0c01ac4541acb766"),
            ("a144410000000000000000000000000000000000000000000000000000000000",
             "r~r~c~b~kp~n~n~b~/9/1p~5a~1/c~1p~1p~1p~1a~/9/9/P~1P~1C~1B~1R~/1P~5B~1/9/C~A~P~N~KA~P~R~N~ w - - 0 1",
             "98ec20c5cd254471f1b321de793bdb85683135b940e2a00558228637ea001baa"),
        ])
        func theDerivationMatchesItsVectors(nonce: String, startFEN: String, digest: String) throws {
            try withCore { core throws in
                var deal = MxqDeal()
                deal.struct_size = UInt32(MemoryLayout<MxqDeal>.size)
                var err = freshError()
                let seed = String(repeating: "0", count: 64)
                let status = mxq_rules_deal(core, MxqGameKind(MXQ_GAME_KIND_JIEQI), seed, nonce, &deal, &err)
                try #require(status == MXQ_OK, "\(describe(status, err))")
                #expect(string(of: deal.start_fen) == startFEN)
                // SHA-256 of thirty-two zero bytes.
                #expect(string(of: deal.commit) == "66687aadf862bd776c8fc18b8e9f8e20089714856ee233b3902a591d0d5f2925")
                #expect(string(of: deal.digest) == digest)
            }
        }
    }
}
