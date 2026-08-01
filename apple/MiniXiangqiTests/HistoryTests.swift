// The library the History screen reads, and the walk the replay screen makes.
//
// Every test here plays real games into a real store through the same path a
// person's game takes, then reads them back through the same surface the screen
// reads them through. Nothing asserts a rule and nothing asserts an order this
// code computed: the order is the core's guarantee, and what is checked is that
// the library reports it and never rearranges it.

import Foundation
import Testing
@testable import MiniXiangqi

@Suite("The History library", .retiringItsCores)
@MainActor
struct HistoryTests {

    /// The mate line, reached after a four-ply shuffle that returns the
    /// position to the start — the same mate, in a longer game, so that two
    /// filed records differ by more than their instant.
    static let longMateLine = ["b1b2", "b7b6", "b2b1", "b6b7"] + GameTests.mateLine

    /// Plays each line into one store and files it, as the app does: a
    /// claimable repetition is claimed, a natural result is confirmed.
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

    // MARK: - What the list shows

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

        // A game still being played is the active game, which is not a History
        // record and must not appear.
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

    // MARK: - Pin

    @Test("Pinning moves a record to the front, and unpinning puts it back")
    func pinningReorders() throws {
        let core = try TestCores.fresh()
        try file([GameTests.mateLine, Self.longMateLine], into: core)
        let library = library(over: core)

        // The older game — last in the list, because the newest is first.
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

    // MARK: - Delete

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

        // The same record again: a record_id is never reissued, so the second
        // deletion is a real refusal from a real store rather than a stand-in's.
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

        // Every id the list can offer belongs to a filed game, so the active
        // game is out of reach by construction. What is checked here is the
        // store's own half of that: it names no active game to the list, and
        // the record ids the list does hold are not the active game's.
        library.load()
        #expect(library.records.map(\.id) == [filed.id],
                "the active game is not a row anything can act on")
        #expect(try core.activeGameExists(), "and reading History did not disturb it")
    }

    // MARK: - The metadata line

    @Test("The line names the mode, the result, the reason, and the move count")
    func theMetadataLineComposes() throws {
        let core = try TestCores.fresh()
        try file([GameTests.mateLine], into: core)
        let record = try #require(library(over: core).records.first)

        let line = record.metadataLine
        #expect(line.contains(record.modeText))
        #expect(line.contains(record.resultText))
        #expect(line.contains(try #require(record.reasonText)),
                "a checkmate says so: the result word alone does not")
        #expect(line.contains(record.moveCountText))
        // Free Play has no controller label, exactly as the turn status has
        // none, because one person controls both sides.
        #expect(record.humanSide == nil)
        #expect(line.split(separator: "·").count == 4,
                "mode · result · reason · moves, and nothing else")
    }

    @Test("An ended-early record says why instead of saying it twice")
    func anEndedEarlyRecordDropsTheReason() {
        // `outcome = none` is true exactly when `end_reason = ended-early`, so
        // the two are one fact and the row states it once.
        let record = RecordSummary(id: 1, game: .miniXiangqi, mode: .freePlay, humanSide: nil,
                                   outcome: .none, reason: .endedEarly,
                                   moveCount: 12, pinned: false, imported: false,
                                   endedAt: .now)
        #expect(record.reasonText == nil)
        #expect(record.resultText == EndReason.endedEarly.text)
        #expect(record.metadataLine.split(separator: "·").count == 3,
                "mode · ended early · moves")
    }

    @Test("A human-versus-AI record names the human's side")
    func aHumanVersusAIRecordNamesTheSide() {
        let record = RecordSummary(id: 1, game: .miniXiangqi,
                                   mode: .humanVersusAI, humanSide: .black,
                                   outcome: .redWins, reason: .resignation,
                                   moveCount: 42, pinned: false, imported: false,
                                   endedAt: .now)
        #expect(record.metadataLine.contains(String(localized: "metadata.youBlack")))
        #expect(record.reasonText != nil,
                "a resignation keeps its reason: 红方获胜 alone does not say whether the player was mated")
        #expect(record.metadataLine.split(separator: "·").count == 5,
                "mode · side · result · reason · moves")
    }
}

@Suite("Replaying a History record", .retiringItsCores)
@MainActor
struct ReplayTests {

    /// A take, and then the shortest repetition available after it: the
    /// soldiers meet on the d-file and Black takes, and the two cannons step
    /// out and back until the position has stood three times. Only a finished
    /// or claimable game can be filed, so this is how a record that contains a
    /// capture is made — and a capture is what a step over one is tested on.
    static let captureThenClaimLine = GameTests.captureLine + GameTests.shuffleLine

    /// A check that is not the end of anything: the cannon reaches the
    /// general's file, the screening soldier steps aside, and a chariot and a
    /// cannon then shuffle the position back to itself three times. Ply 3 is
    /// the check, and it is nowhere near the record's last, so what a checking
    /// landing sounds like can be heard on its own.
    static let checkThenClaimLine =
        GameTests.checkLine + ["d5c5"]
        + ["a1b1", "b7b6", "b1a1", "b6b7", "a1b1", "b7b6", "b1a1", "b6b7"]

    /// Files the line and opens its record for replay through the same call the
    /// screen makes, with the seams a test drives: the animator whose
    /// completions the test fires, and the feedback it listens to.
    private func replay(of line: [String],
                        reduceMotion: Bool = false,
                        soundEnabled: Bool? = true) throws
        -> (replay: Replay, animator: ManualAnimator, heard: FeedbackRecorder,
            notation: [MoveReading], fens: [String]) {
        let core = try TestCores.fresh()
        let played = try openGame(on: core)
        try played.replay(line)
        let notation = played.notation
        // The positions the game itself stood in, ply by ply, captured while it
        // was being played — which is what the walk has to reproduce.
        var fens = [String]()
        for ply in 0...line.count { fens.append(try core.fen(atPly: ply)) }
        // Only a finished or claimable game can be filed today: an ordinary
        // ongoing one is archived by the save-and-continue flow, which is not
        // built yet. A line that is neither is a mistake in the test.
        try #require(played.evaluation.claimAvailable || played.isFinished,
                     "a replay test's line has to be one the app can file")
        if played.evaluation.claimAvailable { played.claimDraw() } else { try played.file() }
        core.endSession()

        let library = HistoryLibrary(store: core.history)
        library.load()
        let record = try #require(library.records.first)
        let animator = ManualAnimator()
        let heard = try FeedbackRecorder(
            defaults: ScratchDefaults.make(soundEnabled: soundEnabled))
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
            // The position arrives with the step's departure and the step is
            // let land before the next, which is how a person walks a game.
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
        // The mate line ends in check, which is what makes it a mate; the
        // check line itself leaves the game running, and an ongoing game is
        // not a History record yet.
        let (replay, _, _, _, _) = try replay(of: GameTests.mateLine)
        defer { replay.close() }

        #expect(replay.checkedGeneral == nil)
        replay.goToEnd()
        #expect(replay.position.inCheck, "the core reports the check")
        #expect(replay.checkedGeneral == Square("d7"),
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

        // Manual navigation pauses playback, which is the accepted behaviour
        // and is also what keeps this test off the clock.
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

        // The walk stops rather than crashing: an invalid handle is the answer
        // the interface promises after a release, and the walk clamps to what
        // it already had.
        replay.stepForward()
        #expect(replay.ply == 0)
        #expect(replay.transit == nil, "and nothing is left travelling")
    }

    // MARK: - A step, travelled

    @Test("A step forward travels the move the way a played move travels")
    func aStepTravels() throws {
        let (replay, animator, _, _, _) = try replay(of: GameTests.mateLine)
        defer { replay.close() }

        replay.stepForward()
        let transit = try #require(replay.transit,
                                   "the board is given a disc to draw on its way")
        #expect(transit.kind == .move)
        #expect(transit.move == Move(text: GameTests.mateLine[0]))
        #expect(transit.piece == Piece(kind: .cannon, side: .red))
        #expect(transit.fading == nil, "nothing stood on b3")
        // The position arrives with the departure — the transit is drawn over
        // it — so the walk is never behind what the transport says.
        #expect(replay.ply == 1)
        #expect(replay.lastMove == Move(text: GameTests.mateLine[0]))

        animator.completeAll()
        #expect(replay.transit == nil, "and the disc is a resting piece again")
        #expect(replay.placement[Square("b3")!] == Piece(kind: .cannon, side: .red),
                "standing where the ply put it")
    }

    @Test("A step over a capture carries the taken disc, and holds for its removal")
    func aStepOverACaptureFades() throws {
        let (replay, animator, _, _, _) = try replay(of: Self.captureThenClaimLine)
        defer { replay.close() }

        // Ply 4 is the take: Black's soldier meets Red's on d4.
        for _ in 0..<3 {
            replay.stepForward()
            animator.completeAll()
        }
        replay.stepForward()

        let transit = try #require(replay.transit)
        #expect(transit.kind == .move)
        #expect(transit.fading?.piece == Piece(kind: .soldier, side: .red),
                "the disc that gives way is the one that was standing there")
        #expect(transit.fading?.at == Square("d4"))
        #expect(replay.transitFade == 1, "and its removal is scheduled against the arrival")

        animator.completeNext()   // the travel: the arrival
        #expect(replay.transit != nil, "the removal's 50 ms tail is still being drawn")
        animator.completeNext()   // the removal's tail
        #expect(replay.transit == nil)
        #expect(replay.placement[Square("d4")!] == Piece(kind: .soldier, side: .black))
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
        #expect(transit.move == Move(from: Square("d4")!, to: Square("d5")!),
                "the mover returns the way it came")
        #expect(transit.piece == Piece(kind: .soldier, side: .black))
        #expect(transit.fading?.piece == Piece(kind: .soldier, side: .red),
                "and what it took reappears where it stood")
        #expect(transit.fading?.at == Square("d4"))
        #expect(replay.transitFade == 1, "the return is scheduled with the departure")

        animator.completeAll()
        #expect(replay.ply == 3)
        #expect(replay.placement[Square("d4")!] == Piece(kind: .soldier, side: .red))
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
        #expect(heard.events.isEmpty, "nothing landed, so nothing is felt or heard")
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
        #expect(heard.events.isEmpty, "and nothing arrived, so nothing sounded")

        // The abandoned step's completion is still parked, and answers to
        // nothing when it comes.
        animator.completeAll()
        #expect(replay.ply == 2)
        #expect(heard.events.isEmpty)

        // And the next step, with nothing in flight, travels as usual.
        replay.stepForward()
        #expect(replay.transit != nil)
        animator.completeAll()
        #expect(heard.events == [.landing])
    }

    @Test("Under Reduce Motion the step arrives without travelling")
    func reduceMotionCollapsesTheStep() throws {
        let (replay, animator, heard, _, fens) = try replay(of: Self.captureThenClaimLine,
                                                            reduceMotion: true)
        defer { replay.close() }
        replay.show(move: 3)

        replay.stepForward()
        // The states survive — the canvas is still given the step, and draws it
        // as a dissolve between the two ends rather than as travel — and the
        // capture's separate removal is not scheduled at all, because there is
        // no arrival for it to be scheduled against.
        let transit = try #require(replay.transit, "the step still arrives")
        #expect(transit.fading?.at == Square("d4"))
        #expect(replay.transitFade == 0, "no removal is drawn beside a dissolve")
        #expect(replay.position.fen == fens[4])

        animator.completeAll()
        #expect(replay.transit == nil)
        #expect(heard.events == [.landing], "and the landing is felt and heard as ever")
        #expect(heard.sounds == [.capture])
    }

    @Test("Autoplay asks for the next ply only after the last one has landed")
    func autoplayWaitsOutTheTravel() {
        // Off the clock, because the rule is arithmetic: the interval is the
        // travel plus a settle, so the next departure is always later than the
        // last arrival, whatever the travel turned out to be.
        for travel in [Motion.travelFloor, Motion.travelCeiling, Motion.crossfade] {
            let interval = Replay.interval(afterTravelling: travel)
            #expect(interval > .seconds(travel),
                    "the next ply never departs before this one lands")
        }
        // And the cadence stays the calm one the screen already walked at: a
        // ply every 780–840 ms, which brackets the 800 ms it was.
        let slowest = Replay.interval(afterTravelling: Motion.travelCeiling)
        #expect(Replay.interval(afterTravelling: Motion.travelFloor) >= .milliseconds(780))
        #expect(slowest <= .milliseconds(840))
    }

    // MARK: - What a replayed landing sounds like

    @Test("An ordinary step sounds the plain tock, and is felt like any landing")
    func aStepSoundsPlain() throws {
        let (replay, animator, heard, _, _) = try replay(of: GameTests.mateLine)
        defer { replay.close() }

        replay.stepForward()
        #expect(heard.events.isEmpty, "the departure is not the arrival")
        animator.completeAll()
        #expect(heard.sounds == [.plain])
        #expect(heard.events == [.landing],
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
        #expect(heard.events == [.landing], "the haptic is unchanged")
    }

    @Test("With sound switched off a replayed step is silent and still felt")
    func theSoundToggleGovernsReplayToo() throws {
        let (replay, animator, heard, _, _) = try replay(of: GameTests.mateLine,
                                                         soundEnabled: false)
        defer { replay.close(); ScratchDefaults.clear() }

        replay.stepForward()
        animator.completeAll()
        #expect(heard.sounds.isEmpty, "one switch, and it is the one play answers to")
        #expect(heard.events == [.landing],
                "and the haptic is untouched: it answers to its own toggle")
    }
}
