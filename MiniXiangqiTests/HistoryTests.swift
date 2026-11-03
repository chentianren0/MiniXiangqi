import Foundation
import Testing
@testable import MiniXiangqi

@Suite("The History library", .retiringItsCores)
@MainActor
struct HistoryTests {
    static let longMateLine = ["b1b2", "b7b6", "b2b1", "b6b7"] + GameTests.mateLine

    @discardableResult
    private func file(_ lines: [[String]], into core: Core) throws -> Core {
        for line in lines {
            core.endSession()
            let game = try openGame(on: core)
            try game.replay(line)
            if game.evaluation.claimAvailable {
                game.claimDraw()
            } else {
                try game.file()
            }
        }
        core.endSession()
        return core
    }

    private func library(over core: Core) -> HistoryLibrary {
        let library = HistoryLibrary(store: core.history)
        library.load()
        return library
    }

    @Test("An empty library is empty, and says so only once it has answered")
    func absenceIsTheEmptyState() throws {
        let core = try TestCores.fresh()
        let library = HistoryLibrary(store: core.history)
        #expect(!library.isEmpty, "nothing may be claimed before the store has answered")

        library.load()
        #expect(library.loaded)
        #expect(library.isEmpty)
        #expect(library.records.isEmpty)
        #expect(library.failure == nil)
    }

    @Test("The list is the store's, newest first, and the active game is not in it")
    func theListReflectsTheStore() throws {
        let core = try TestCores.fresh()
        try file([GameTests.mateLine, Self.longMateLine], into: core)

        let playing = try openGame(on: core)
        try playing.replay(["b1b4"])

        let library = library(over: core)
        #expect(library.records.count == 2, "two filed games, and only those two")
        #expect(library.records.map(\.moveCount) == [7, 3],
                "the most recently filed comes first")
        #expect(library.records.allSatisfy { $0.outcome == .redWins })
        #expect(library.records.allSatisfy { $0.reason == .checkmate })
        #expect(library.records.allSatisfy { $0.mode == .freePlay })
        #expect(library.records.allSatisfy { !$0.pinned })
        #expect(library.pinnedRecords.isEmpty)
        #expect(library.unpinnedRecords.count == 2)
    }

    @Test("A claimed draw and a confirmed mate keep their own outcomes")
    func eachRecordKeepsItsOwnResult() throws {
        let core = try TestCores.fresh()
        try file([GameTests.mateLine, GameTests.shuffleLine], into: core)

        let library = library(over: core)
        let draw = try #require(library.records.first)
        #expect(draw.outcome == .draw)
        #expect(draw.reason == .threefoldRepetition)
        #expect(draw.moveCount == 8)

        let mate = try #require(library.records.last)
        #expect(mate.outcome == .redWins)
        #expect(mate.reason == .checkmate)
        #expect(mate.moveCount == 3)
    }

    @Test("Pinning moves a record to the front, and unpinning puts it back")
    func pinningReorders() throws {
        let core = try TestCores.fresh()
        try file([GameTests.mateLine, Self.longMateLine], into: core)
        let library = library(over: core)

        let older = try #require(library.records.last)
        library.setPinned(true, on: older)

        #expect(library.records.first?.id == older.id,
                "a pinned record comes before every unpinned one")
        #expect(library.records.first?.pinned == true)
        #expect(library.pinnedRecords.map(\.id) == [older.id],
                "and the pinned group is exactly it")
        #expect(library.unpinnedRecords.count == 1)

        library.setPinned(false, on: try #require(library.records.first))
        #expect(library.records.last?.id == older.id, "unpinned, it is the older game again")
        #expect(library.pinnedRecords.isEmpty)
    }

    @Test("Deletion removes the record permanently and leaves the rest alone")
    func deletionIsPermanent() throws {
        let core = try TestCores.fresh()
        try file([GameTests.mateLine, Self.longMateLine], into: core)
        let library = library(over: core)
        let survivor = try #require(library.records.first).id
        let doomed = try #require(library.records.last)

        library.delete(doomed)

        #expect(library.deletionFailure == nil)
        #expect(library.records.map(\.id) == [survivor], "the other game is untouched")
        #expect(try core.historyCount() == 1, "and the store agrees")
    }

    @Test("A deletion the store refuses is recorded for the retry, and changes nothing")
    func aRefusedDeletionChangesNothing() throws {
        let core = try TestCores.fresh()
        try file([GameTests.mateLine], into: core)
        let library = library(over: core)
        let record = try #require(library.records.first)

        library.delete(record)
        #expect(library.records.isEmpty)

        library.delete(record)
        #expect(library.deletionFailure != nil, "the refusal is held for the alert")
        #expect(try core.historyCount() == 0, "and nothing else changed")

        library.dismissDeletionFailure()
        #expect(library.deletionFailure == nil)
    }

    @Test("Deleting the active game's record is refused: it is not a History record")
    func theActiveGameCannotBeDeleted() throws {
        let core = try TestCores.fresh()
        try file([GameTests.mateLine], into: core)
        let library = library(over: core)
        let filed = try #require(library.records.first)

        let playing = try openGame(on: core)
        try playing.replay(["b1b4"])
        #expect(try core.activeGameExists())

        library.load()
        #expect(library.records.map(\.id) == [filed.id],
                "the active game is not a row anything can act on")
        #expect(try core.activeGameExists(), "and reading History did not disturb it")
    }
}

@Suite("Replaying a History record", .retiringItsCores)
@MainActor
struct ReplayTests {
    static let captureThenClaimLine = GameTests.captureLine + GameTests.shuffleLine

    static let checkThenClaimLine =
        GameTests.checkLine + ["d5c5"]
        + ["a1b1", "b7b6", "b1a1", "b6b7", "a1b1", "b7b6", "b1a1", "b6b7"]

    static let fiveInARowLine = ["h8", "a1", "i8", "a15", "j8", "o1",
                                 "k8", "o15", "l8"]

    private func replay(of line: [String],
                        configuration: (Core) throws -> GameConfiguration
                            = { _ in .freePlay(game: .miniXiangqi) },
                        reduceMotion: Bool = false) throws
        -> (replay: Replay, animator: ManualAnimator, heard: FeedbackRecorder,
            notation: [MoveReading], fens: [String]) {
        let core = try TestCores.fresh()
        try core.create(try configuration(core))
        let played = try Game(core: core)
        try played.replay(line)
        let notation = played.notation
        var fens = [String]()
        for ply in 0...line.count { fens.append(try core.fen(atPly: ply)) }
        try #require(played.evaluation.claimAvailable || played.isFinished,
                     "a replay test's line has to be one the app can file")
        if played.evaluation.claimAvailable { played.claimDraw() } else { try played.file() }
        core.endSession()

        let library = HistoryLibrary(store: core.history)
        library.load()
        let record = try #require(library.records.first)
        let animator = ManualAnimator()
        let heard = FeedbackRecorder()
        switch library.replay(of: record,
                              policy: MotionPolicy(reduceMotion: reduceMotion),
                              animator: animator.animator,
                              feedback: heard.feedback) {
        case .success(let replay): return (replay, animator, heard, notation, fens)
        case .failure(let error): throw error
        }
    }

    @Test("Replay opens at the initial position with no move behind it")
    func replayOpensAtTheStart() throws {
        let (replay, _, _, notation, fens) = try replay(of: GameTests.mateLine)
        defer { replay.close() }

        #expect(replay.ply == 0)
        #expect(replay.isAtStart)
        #expect(!replay.isAtEnd)
        #expect(replay.lastMove == nil, "no brackets at an initial position")
        #expect(replay.position.fen == fens[0])
        #expect(replay.moves == GameTests.mateLine)
        #expect(replay.notation == notation,
                "the record reads back in the words the sitting itself wrote")
        #expect(!replay.flipped, "Free Play opens Red at the bottom")
        #expect(replay.carriesFlip, "and a board of pieces keeps its flip control")
    }

    @Test("A placement record replays unflipped, with no flip control")
    func placementReplayCarriesNoFlip() throws {
        let (replay, _, _, _, _) = try replay(
            of: Self.fiveInARowLine,
            configuration: { _ in
                .humanVersusAI(game: .gomoku15, humanSide: .black,
                               level: .fast, choice: .aiFirst)
            })
        defer { replay.close() }

        #expect(replay.record.humanSide == .black,
                "the machine moved first, so the human holds the white stones")
        #expect(!replay.carriesFlip, "stones have no orientation to read")
        #expect(!replay.flipped,
                "and a board with no orientation opens as it is drawn")
        #expect(replay.moves == Self.fiveInARowLine,
                "and it is the placement record it says it is")
    }

    @Test("A dealt record replays: its reveals step both ways, and its ending discloses")
    func aDealtRecordReplaysItsRevealsAndItsEnding() throws {
        let (replay, animator, _, _, fens) = try replay(
            of: JieqiTests.claimableLine,
            configuration: { try .freePlay(game: .jieqi,
                                           startFEN: $0.deal(.jieqi).startFEN) })
        defer { replay.close() }
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
        let (replay, animator, _, _, fens) = try replay(of: GameTests.shuffleLine)
        defer { replay.close() }

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

    @Test("The transport reaches both ends and stops at them")
    func theTransportIsBounded() throws {
        let (replay, _, _, _, _) = try replay(of: GameTests.shuffleLine)
        defer { replay.close() }
        let plies = GameTests.shuffleLine.count

        replay.stepBack()
        #expect(replay.ply == 0, "there is nothing before the initial position")

        replay.goToEnd()
        #expect(replay.ply == plies)
        #expect(replay.isAtEnd)
        replay.stepForward()
        #expect(replay.ply == plies, "and nothing after the last")

        replay.stepBack()
        #expect(replay.ply == plies - 1)
        replay.goToStart()
        #expect(replay.ply == 0)

        replay.show(move: 2)
        #expect(replay.ply == 2, "the move list jumps to a selected move")
    }

    @Test("A checked general is ringed at the ply that checks it, and not before")
    func checkFollowsTheWalk() throws {
        let (replay, _, _, _, _) = try replay(of: GameTests.mateLine)
        defer { replay.close() }

        #expect(replay.checkedGeneral == nil)
        replay.goToEnd()
        #expect(replay.position.inCheck, "the core reports the check")
        #expect(replay.checkedGeneral == Square("d7", on: GameKind.miniXiangqi.board),
                "and the rings go round the general it is about")
        replay.stepBack()
        #expect(replay.checkedGeneral == nil, "walking back walks the check back too")
    }

    @Test("Autoplay walks to the end and stops there")
    func autoplayStopsAtTheEnd() throws {
        let (replay, _, _, _, _) = try replay(of: GameTests.mateLine)
        defer { replay.close() }

        replay.toggleAutoplay()
        #expect(replay.autoplaying, "playback starts only after a user action, and this was one")

        replay.stepForward()
        #expect(!replay.autoplaying)
        #expect(replay.ply == 1)

        replay.goToEnd()
        replay.toggleAutoplay()
        #expect(!replay.autoplaying, "there is nothing left to play at the final position")
    }

    @Test("Flipping the board changes presentation only, and pauses playback")
    func flippingIsPresentationOnly() throws {
        let (replay, _, _, _, fens) = try replay(of: GameTests.shuffleLine)
        defer { replay.close() }
        replay.toggleAutoplay()

        replay.flipped = true

        #expect(!replay.autoplaying, "a flip pauses playback")
        #expect(replay.ply == 0)
        #expect(replay.position.fen == fens[0], "and changes nothing about the position")
    }

    @Test("A closed replay releases its session and answers nothing further")
    func closingReleasesTheSession() throws {
        let (replay, _, _, _, _) = try replay(of: GameTests.mateLine)
        replay.close()

        replay.stepForward()
        #expect(replay.ply == 0)
        #expect(replay.transit == nil, "and nothing is left travelling")
    }

    @Test("A step forward travels the move the way a played move travels")
    func aStepTravels() throws {
        let (replay, animator, _, _, _) = try replay(of: GameTests.mateLine)
        defer { replay.close() }

        replay.stepForward()
        let transit = try #require(replay.transit,
                                   "the board is given a disc to draw on its way")
        #expect(transit.kind == .move)
        #expect(transit.move == Move(text: GameTests.mateLine[0],
                                    on: GameKind.miniXiangqi.board))
        #expect(transit.piece == Piece(kind: .cannon, side: .red))
        #expect(transit.fading == nil, "nothing stood on b3")
        #expect(replay.ply == 1)
        #expect(replay.lastMove == Move(text: GameTests.mateLine[0],
                                       on: GameKind.miniXiangqi.board))

        animator.completeAll()
        #expect(replay.transit == nil, "and the disc is a resting piece again")
        #expect(replay.placement[Square("b3", on: GameKind.miniXiangqi.board)!]
                == Piece(kind: .cannon, side: .red),
                "standing where the ply put it")
    }

    @Test("A step over a capture carries the taken disc, and holds for its removal")
    func aStepOverACaptureFades() throws {
        let (replay, animator, _, _, _) = try replay(of: Self.captureThenClaimLine)
        defer { replay.close() }

        for _ in 0..<3 {
            replay.stepForward()
            animator.completeAll()
        }
        replay.stepForward()

        let transit = try #require(replay.transit)
        #expect(transit.kind == .move)
        #expect(transit.fading?.piece == Piece(kind: .soldier, side: .red),
                "the disc that gives way is the one that was standing there")
        #expect(transit.fading?.at == Square("d4", on: GameKind.miniXiangqi.board))
        #expect(replay.transitFade == 1, "and its removal is scheduled against the arrival")

        animator.completeNext()   // the travel: the arrival
        #expect(replay.transit != nil, "the removal's 50 ms tail is still being drawn")
        animator.completeNext()   // the removal's tail
        #expect(replay.transit == nil)
        #expect(replay.placement[Square("d4", on: GameKind.miniXiangqi.board)!]
                == Piece(kind: .soldier, side: .black))
    }

    @Test("A step back travels the move in reverse and brings the taken piece back")
    func aStepBackReversesTheMove() throws {
        let (replay, animator, _, _, _) = try replay(of: Self.captureThenClaimLine)
        defer { replay.close() }
        replay.show(move: 4)      // a jump, straight to the position after the take
        #expect(replay.transit == nil, "which is a cut")

        replay.stepBack()
        let transit = try #require(replay.transit)
        #expect(transit.kind == .undo, "read backwards, exactly as an Undo is drawn")
        #expect(transit.move == Move(
            from: Square("d4", on: GameKind.miniXiangqi.board)!,
            to: Square("d5", on: GameKind.miniXiangqi.board)!),
                "the mover returns the way it came")
        #expect(transit.piece == Piece(kind: .soldier, side: .black))
        #expect(transit.fading?.piece == Piece(kind: .soldier, side: .red),
                "and what it took reappears where it stood")
        #expect(transit.fading?.at == Square("d4", on: GameKind.miniXiangqi.board))
        #expect(replay.transitFade == 1, "the return is scheduled with the departure")

        animator.completeAll()
        #expect(replay.ply == 3)
        #expect(replay.placement[Square("d4", on: GameKind.miniXiangqi.board)!]
                == Piece(kind: .soldier, side: .red))
        #expect(replay.transit == nil)
    }

    @Test("A jump is a cut, however far it goes")
    func aJumpDoesNotAnimate() throws {
        let (replay, _, heard, _, fens) = try replay(of: GameTests.mateLine)
        defer { replay.close() }

        replay.goToEnd()
        #expect(replay.ply == 3)
        #expect(replay.position.fen == fens[3], "the position asked for, at once")
        #expect(replay.transit == nil, "and no cascade of three moves to watch")
        #expect(replay.landings == 0, "nothing landed, so nothing is felt or heard")
        #expect(heard.sounds.isEmpty)

        replay.goToStart()
        #expect(replay.ply == 0)
        #expect(replay.transit == nil)

        replay.show(move: 2)
        #expect(replay.ply == 2, "a row two plies away is a jump too")
        #expect(replay.transit == nil)
    }

    @Test("A step arriving while one travels re-targets rather than queuing")
    func aRapidStepRetargets() throws {
        let (replay, animator, heard, _, fens) = try replay(of: GameTests.mateLine)
        defer { replay.close() }

        replay.stepForward()
        #expect(replay.transit != nil)
        replay.stepForward()

        #expect(replay.ply == 2, "the second press is answered, not queued behind the first")
        #expect(replay.position.fen == fens[2])
        #expect(replay.transit == nil,
                "re-targeting a travel cuts it: the abandoned disc lands nowhere")
        #expect(replay.landings == 0, "and nothing arrived, so nothing sounded")

        animator.completeAll()
        #expect(replay.ply == 2)
        #expect(replay.landings == 0)

        replay.stepForward()
        #expect(replay.transit != nil)
        animator.completeAll()
        #expect(replay.landings == 1)
    }

    @Test("Under Reduce Motion the step arrives without travelling")
    func reduceMotionCollapsesTheStep() throws {
        let (replay, animator, heard, _, fens) = try replay(of: Self.captureThenClaimLine,
                                                            reduceMotion: true)
        defer { replay.close() }
        replay.show(move: 3)

        replay.stepForward()
        let transit = try #require(replay.transit, "the step still arrives")
        #expect(transit.fading?.at == Square("d4", on: GameKind.miniXiangqi.board))
        #expect(replay.transitFade == 0, "no removal is drawn beside a dissolve")
        #expect(replay.position.fen == fens[4])

        animator.completeAll()
        #expect(replay.transit == nil)
        #expect(replay.landings == 1, "and the landing is felt and heard as ever")
        #expect(heard.sounds == [.capture])
    }

    @Test("Autoplay asks for the next ply only after the last one has landed")
    func autoplayWaitsOutTheTravel() {
        for travel in [Motion.travelFloor, Motion.travelCeiling, Motion.crossfade] {
            let interval = Replay.interval(afterTravelling: travel)
            #expect(interval > .seconds(travel),
                    "the next ply never departs before this one lands")
        }
        let slowest = Replay.interval(afterTravelling: Motion.travelCeiling)
        #expect(Replay.interval(afterTravelling: Motion.travelFloor) >= .milliseconds(780))
        #expect(slowest <= .milliseconds(840))
    }

    @Test("An ordinary step sounds the plain tock, and is felt like any landing")
    func aStepSoundsPlain() throws {
        let (replay, animator, heard, _, _) = try replay(of: GameTests.mateLine)
        defer { replay.close() }

        replay.stepForward()
        #expect(replay.landings == 0, "the departure is not the arrival")
        animator.completeAll()
        #expect(heard.sounds == [.plain])
        #expect(replay.landings == 1,
                "felt as every landing is: replay's landings are landings")
    }

    @Test("A step over a capture sounds like a capture")
    func aCaptureStepSoundsLikeACapture() throws {
        let (replay, animator, heard, _, _) = try replay(of: Self.captureThenClaimLine)
        defer { replay.close() }
        replay.show(move: 3)

        replay.stepForward()
        animator.completeAll()
        #expect(heard.sounds == [.capture])
    }

    @Test("A step into check sounds the accent")
    func aCheckingStepSoundsTheAccent() throws {
        let (replay, animator, heard, _, _) = try replay(of: Self.checkThenClaimLine)
        defer { replay.close() }
        replay.show(move: 2)

        replay.stepForward()
        #expect(replay.checkedGeneral != nil, "the ply gives check")
        #expect(!replay.isFinalPosition, "and the game goes on for eight more plies")
        animator.completeAll()
        #expect(heard.sounds == [.check])
    }

    @Test("The step that ends the game sounds the conclusion")
    func theFinalStepSoundsTheConclusion() throws {
        let (replay, animator, heard, _, _) = try replay(of: GameTests.mateLine)
        defer { replay.close() }
        replay.show(move: 2)

        replay.stepForward()
        animator.completeAll()
        #expect(replay.isFinalPosition, "the record's own outcome says the game ended here")
        #expect(heard.sounds == [.conclusion],
                "one rule: the arrived position is finished, whoever is watching it")
        #expect(replay.landings == 1, "the haptic is unchanged")
    }
}
