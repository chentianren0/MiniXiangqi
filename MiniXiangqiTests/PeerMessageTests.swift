import Foundation
import Testing
@testable import MiniXiangqi

@Suite("What two devices say to each other")
struct PeerMessageTests {
    static let game = UUID(uuidString: "0B34A2F1-7C1D-4E5B-9A60-1D2E3F405162")!

    static let every: [PeerMessage] = [
        .hello(peer: "6F1C", name: "iPhone 6F1C"),
        .propose(game: game, kind: .jieqi, proposerSide: .black,
                 seed: String(repeating: "ab", count: 32)),
        .propose(game: game, kind: .renju, proposerSide: .red, seed: nil),
        .accept(game: game),
        .decline(game: game, busy: true),
        .move(game: game, ply: 7, move: "b1b3"),
        .offerDraw(game: game, ply: 8),
        .askTakeback(game: game, ply: 8),
        .acceptTakeback(game: game, ply: 8),
        .end(game: game, ending: PeerEnding(outcome: .blackWins, reason: .resignation, length: 8)),
        .resume(game: game, moves: ["b1b3", "b7b6"], takebacks: [1],
                ending: PeerEnding(outcome: .draw, reason: .agreedDraw, length: 2)),
        .resume(game: game, moves: [], takebacks: [], ending: nil),
        .gone(game: game),
    ]

    @Test("Every message comes back from JSON as it went")
    func everyMessageRoundTrips() throws {
        for message in Self.every {
            let data = try JSONEncoder().encode(message)
            #expect(try JSONDecoder().decode(PeerMessage.self, from: data) == message)
        }
    }

    @Test("A message is one object named by its case")
    func theShapeOnTheWire() throws {
        let data = try JSONEncoder().encode(PeerMessage.move(game: Self.game, ply: 7, move: "b1b3"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Array(object.keys) == ["move"])
        let fields = try #require(object["move"] as? [String: Any])
        #expect(fields["game"] as? String == Self.game.uuidString)
        #expect(fields["ply"] as? Int == 7)
        #expect(fields["move"] as? String == "b1b3")
    }

    // MARK: - Two endings, one rule

    private static func resign(_ side: Side, at ply: Int) -> PeerEnding {
        PeerEnding(outcome: .win(for: side.opponent), reason: .resignation, length: ply)
    }

    private static let mate = PeerEnding(outcome: .redWins, reason: .checkmate, length: 5,
                                         byRules: true)

    @Test("The earlier ply wins, whichever device asks")
    func theEarlierPlyWins() {
        let early = Self.resign(.red, at: 3)
        #expect(PeerEnding.settled(early, Self.mate) == early)
        #expect(PeerEnding.settled(Self.mate, early) == early)
    }

    @Test("On an equal ply the rules result beats the chosen ending")
    func theRulesWinATie() {
        // The mate's deciding move is the one at index 4; a resignation made
        // with four moves on the board crossed it.
        let crossed = Self.resign(.black, at: 4)
        #expect(PeerEnding.settled(crossed, Self.mate) == Self.mate)
        #expect(PeerEnding.settled(Self.mate, crossed) == Self.mate)
    }

    @Test("A draw beats a resignation on one ply, and two resignations are a draw")
    func chosenEndingsOnOnePly() {
        let draw = PeerEnding(outcome: .draw, reason: .agreedDraw, length: 6)
        let red = Self.resign(.red, at: 6)
        let black = Self.resign(.black, at: 6)
        #expect(PeerEnding.settled(red, draw) == draw)
        #expect(PeerEnding.settled(draw, red) == draw)
        let both = PeerEnding(outcome: .draw, reason: .mutualResignation, length: 6)
        #expect(PeerEnding.settled(red, black) == both)
        #expect(PeerEnding.settled(black, red) == both)
        #expect(PeerEnding.settled(both, red) == both)
        #expect(PeerEnding.settled(red, red) == red)
    }

    @Test("Ended early yields to any result, whatever its ply")
    func endedEarlyYields() {
        let early = PeerEnding.endedEarly(after: 2)
        let late = Self.resign(.red, at: 9)
        #expect(PeerEnding.settled(early, late) == late)
        #expect(PeerEnding.settled(late, early) == late)
        #expect(PeerEnding.settled(early, Self.mate) == Self.mate)
        #expect(PeerEnding.settled(early, .endedEarly(after: 4)) == .endedEarly(after: 4))
    }
}
