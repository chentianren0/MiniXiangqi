import Foundation
import Testing
@testable import MiniXiangqi

@Suite("Replaying a History record", .retiringItsCores)
@MainActor
struct ReplayTests {
    /// A composed Xiangqi start with Black to move, and the generals' walk
    /// that brings it round three times.
    static let blackFirst = "3k5/9/9/9/9/9/9/9/9/4K4 b - - 0 1"
    static let blackFirstLine = (0..<2).flatMap { _ in ["d10d9", "e1e2", "d9d10", "e2e1"] }

    /// Plays `line`, files it, and opens the record's replay. Also answers the
    /// sitting's own notation and positions, for the replay to be held to, and
    /// the library, which the record lives only as long as.
    private func replay(of line: [String],
                        configuration: (Core) throws -> GameConfiguration
                            = { _ in .freePlay(game: .miniXiangqi) }) throws
        -> (replay: Replay, animator: ManualAnimator, notation: [MoveReading], fens: [String],
            library: GameLibrary) {
        let library = try TestLibraries.fresh()
        try library.create(try configuration(library.core))
        let played = try Game(library: library)
        try played.replay(line)
        let notation = played.notation
        let fens = try (0...line.count).map { try library.fen(atPly: $0) }
        try #require(played.evaluation.claimAvailable || played.isFinished,
                     "a replay test's line has to be one the app can file")
        if played.evaluation.claimAvailable { played.claimDraw() } else { try played.file() }

        let history = HistoryLibrary(library: library)
        history.load()
        let record = try #require(history.records.first)
        let animator = ManualAnimator()
        let replay = try history.replay(of: record, policy: MotionPolicy(reduceMotion: false),
                                        animator: animator.animator,
                                        feedback: FeedbackRecorder().feedback).get()
        return (replay, animator, notation, fens, library)
    }

    @Test("A dealt record replays: its reveals step both ways, and its ending discloses")
    func aDealtRecordReplaysItsRevealsAndItsEnding() throws {
        let (replay, animator, _, fens, library) = try replay(
            of: JieqiTests.claimableLine,
            configuration: { try .freePlay(game: .jieqi, startFEN: $0.deal(.jieqi).startFEN) })
        defer { replay.close(); _ = library }
        let board = GameKind.jieqi.board
        let square = { (name: String) in Square(name, on: board)! }
        let start = Placement(fen: fens[0], game: .jieqi)
        let taken = try #require(start.concealedIdentity(at: square("b1")))

        #expect(replay.captured.taken.count == 1, "one piece was taken in this game")
        let capture = try #require(replay.captured.taken.first)
        #expect(capture.side == .red)
        #expect(capture.wasFaceDown)
        #expect(capture.kind == taken, "and the record says what it was")
        #expect(!replay.disclosesTheDeal, "the initial position is where the game began")

        replay.stepForward()
        let forward = try #require(replay.transit)
        #expect(forward.piece.isFaceDown)
        #expect(forward.revealed?.isFaceDown == false, "it arrives face up")
        animator.completeAll()
        #expect(replay.placement[square("b4")]?.isFaceDown == false)
        #expect(replay.placement[square("b3")] == nil)

        replay.stepBack()
        let backward = try #require(replay.transit)
        #expect(!backward.piece.isFaceDown, "it leaves the face it turned up")
        #expect(backward.revealed?.isFaceDown == true, "and returns face down")
        animator.completeAll()
        #expect(replay.placement[square("b3")]?.isFaceDown == true)
        #expect(replay.position.fen == fens[0])

        replay.goToEnd()
        #expect(replay.isFinalPosition)
        #expect(replay.disclosesTheDeal)
        #expect(replay.placement[square("a1")]?.isFaceDown == true,
                "the position is the position: what changed is what may be shown")
        replay.stepBack()
        #expect(!replay.disclosesTheDeal,
                "and a walk out of it is a walk back into the game as it was played")
    }

    @Test("The walk is the core's: every ply is the position the game stood in")
    func theWalkMatchesThePositionsPlayed() throws {
        let (replay, animator, notation, fens, library) = try replay(of: GameTests.shuffleLine)
        defer { replay.close(); _ = library }

        #expect(replay.notation == notation,
                "the record reads back in the words the sitting itself wrote")
        #expect(replay.position.fen == fens[0])
        while !replay.isAtEnd {
            replay.stepForward()
            #expect(replay.position.fen == fens[replay.ply],
                    "ply \(replay.ply) is the position the game stood in")
            #expect(replay.lastMove?.text == GameTests.shuffleLine[replay.ply - 1],
                    "the brackets mark the move that produced what is on screen")
            animator.completeAll()
        }
        #expect(replay.ply == GameTests.shuffleLine.count, "the whole line, and no more")
    }

    @Test("A checked general is ringed at the ply that checks it, and not before")
    func checkFollowsTheWalk() throws {
        let (replay, _, _, _, library) = try replay(of: GameTests.mateLine)
        defer { replay.close(); _ = library }

        #expect(replay.checkedGeneral == nil)
        replay.goToEnd()
        #expect(replay.position.inCheck, "the core reports the check")
        #expect(replay.checkedGeneral == Square("d7", on: GameKind.miniXiangqi.board),
                "and the rings go round the general it is about")
        replay.stepBack()
        #expect(replay.checkedGeneral == nil, "walking back walks the check back too")
    }

    @Test("A composed start with Black to move replays from that start, Black first")
    func aComposedStartReplaysBlackFirst() throws {
        let (replay, animator, _, fens, library) = try replay(
            of: Self.blackFirstLine,
            configuration: { _ in .freePlay(game: .xiangqi, startFEN: Self.blackFirst) })
        defer { replay.close(); _ = library }

        #expect(replay.record.setup == Self.blackFirst)
        #expect(replay.position.fen == Self.blackFirst, "the walk begins at the composed start")
        #expect(replay.firstMover == .black, "and Black made ply 0")
        #expect(replay.position.sideToMove == .black)
        #expect(MovePairing(plies: replay.moves.count, firstMover: replay.firstMover).rows.first
                == MovePairing.Row(number: 1, red: nil, black: 0),
                "so the move list opens with an empty Red cell")

        replay.stepForward()
        animator.completeAll()
        #expect(replay.position.fen == fens[1])
        #expect(replay.position.sideToMove == .red)
    }
}
