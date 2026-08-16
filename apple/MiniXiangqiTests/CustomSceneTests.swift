// The Custom Scene editor, and the games that begin from what it composes.
//
// docs/interaction-design.md, "Custom Scene": an empty interactive board, a
// palette of the standard set with what remains of each, a tap that places and
// a tap that removes, a side-to-move choice, live validation carrying one plain
// reason, and 开始对局 enabled on a position that is both legal and playable.
//
// **Every rule here is the core's.** These cases assert which of the core's
// answers the editor shows and what it spells to ask the question — the FEN, the
// ordering of the two questions, and the class the reason is chosen by. None of
// them asserts a rule: the fixtures under fixtures/rules/ are where the
// predicate itself is pinned, and a case here that re-stated a clause would be
// a second authority over it.

import Foundation
import MiniXiangqiCore
import Testing
@testable import MiniXiangqi

@Suite("The Custom Scene editor", .retiringItsCores)
@MainActor
struct CustomSceneTests {

    private static let board = CustomScene.game.board

    /// A legal, playable scene: the two generals and nothing else, Black to
    /// move.
    private static let bareScene = "3k5/9/9/9/9/9/9/9/9/4K4 b - - 0 1"

    /// A position the predicate accepts and that is already decided — Black is
    /// checkmated where it stands, so it is a legal setup and no game to play.
    private static let decidedScene = "3k5/9/9/9/9/9/9/9/4R4/3RK4 b - - 0 1"

    private func square(_ name: String) throws -> Square {
        try #require(Square(name, on: Self.board), "\(name) is a point of this board")
    }

    /// Picks each entry up and puts it down, which is the whole of the editor's
    /// input — there is no other way a piece reaches the board.
    private func place(_ scene: CustomScene, _ pieces: [(String, Piece)]) throws {
        for (name, piece) in pieces {
            scene.pick(piece)
            scene.tap(try square(name))
        }
    }

    private static func red(_ kind: PieceKind) -> Piece { Piece(kind: kind, side: .red) }
    private static func black(_ kind: PieceKind) -> Piece { Piece(kind: kind, side: .black) }

    /// The two generals, which every startable scene needs and which the count
    /// clause names the side of until they are there.
    private func generals(_ scene: CustomScene) throws {
        try place(scene, [("e1", Self.red(.general)), ("d10", Self.black(.general))])
    }

    // MARK: - What the editor spells

    @Test("The composed position is the placement, the chosen side, and a start's own counters")
    func theComposedPositionIsWhatTheCoreIsAsked() throws {
        let core = try TestCores.fresh()
        let scene = CustomScene(core: core)

        #expect(scene.fen == "9/9/9/9/9/9/9/9/9/9 w - - 0 1",
                "an empty board, Red to move, with halfmove 0 and fullmove 1")

        try generals(scene)
        #expect(scene.fen == "3k5/9/9/9/9/9/9/9/9/4K4 w - - 0 1",
                "the highest rank first, and a run of empty points in decimal")

        scene.sideToMove = .black
        #expect(scene.fen == Self.bareScene, "the side chosen is the side to move")
    }

    @Test("A tap places the held piece and a tap takes it back off")
    func aTapPlacesAndATapRemoves() throws {
        let core = try TestCores.fresh()
        let scene = CustomScene(core: core)
        let cannon = Self.red(.cannon)
        #expect(scene.remaining(cannon) == 2, "the standard set's own complement")

        scene.pick(cannon)
        scene.tap(try square("b3"))
        #expect(scene.pieces[try square("b3")] == cannon)
        #expect(scene.remaining(cannon) == 1, "one of the two is on the board")

        // The entry stays held, so the second one is a tap and not a second
        // pick — and once it is spent the entry is no longer held.
        scene.tap(try square("h3"))
        #expect(scene.remaining(cannon) == 0)
        #expect(!scene.isHeld(cannon), "an entry with none left is not the held one")
        scene.pick(cannon)
        #expect(!scene.isHeld(cannon), "and cannot be picked up again")

        scene.tap(try square("b3"))
        #expect(scene.pieces[try square("b3")] == nil, "a tap on a piece takes it off")
        #expect(scene.remaining(cannon) == 1, "and returns it to the palette")
    }

    @Test("The palette is the standard set, read off the game's own frozen start")
    func thePaletteIsTheStandardSet() throws {
        let core = try TestCores.fresh()
        let scene = CustomScene(core: core)
        let start = Placement(fen: Core.startFEN(for: CustomScene.game),
                              game: CustomScene.game)
        var counted: [Piece: Int] = [:]
        for rank in 0..<Self.board.rankCount {
            for file in 0..<Self.board.fileCount {
                guard let piece = start[Square(file: file, rank: rank)] else { continue }
                counted[piece, default: 0] += 1
            }
        }
        #expect(CustomScene.entries.count == counted.count,
                "one entry per piece the opening array holds — both sides, seven kinds")
        for entry in CustomScene.entries {
            #expect(scene.remaining(entry) == counted[entry],
                    "\(entry) starts with as many as the frozen start gives it")
        }
    }

    // MARK: - The point that will not take the piece

    /// A held piece offered to a point the core reports as no place for it does
    /// not land, and the page is handed the sentence to say at that moment.
    ///
    /// The class and the point are the core's, and which sentence each class
    /// comes to is pinned above. What is asserted here is what the refusal
    /// *does*: the draft is untouched, the piece is still held, and the very
    /// next point that does take it takes it.
    @Test("A point the core refuses the piece at does not take it, and says why")
    func anIllegalPointRefusesTheHeldPiece() throws {
        let core = try TestCores.fresh()
        let scene = CustomScene(core: core)
        try generals(scene)
        let advisor = Self.red(.advisor)

        let outside = try square("c1")
        scene.pick(advisor)
        scene.tap(outside)

        let refusal = try #require(scene.refusal, "the point answered")
        #expect(refusal.square == outside)
        #expect(refusal.piece == advisor)
        #expect(!refusal.reason.isEmpty, "and it answered with a sentence")
        #expect(scene.pieces[outside] == nil, "and the draft did not change")
        #expect(scene.remaining(advisor) == 2)
        #expect(scene.isHeld(advisor), "the piece is still in hand")
        #expect(scene.verdict == .startable, "nor did what the core says about it")

        // The point that does take it takes it, and the refusal is spent.
        scene.tap(try square("d1"))
        #expect(scene.pieces[try square("d1")] == advisor)
        #expect(scene.refusal == nil)
    }

    /// The refusals that are about the whole position rather than about the
    /// point just touched stay placeable, because a composer builds through
    /// them: the piece lands and the standing reason line reports it.
    @Test("A position-wide refusal is an intermediate state and still places")
    func aPositionWideRefusalStillPlaces() throws {
        let core = try TestCores.fresh()
        let scene = CustomScene(core: core)
        scene.sideToMove = .black
        try generals(scene)

        let chariot = Self.black(.chariot)
        scene.pick(chariot)
        scene.tap(try square("e10"))

        #expect(scene.refusal == nil, "the point took it")
        #expect(scene.pieces[try square("e10")] == chariot)
        #expect(scene.verdict == .violation(SetupViolation(rule: .opponentInCheck,
                                                           side: .red, square: "e1")),
                "and the standing reason is what reports the position")
    }

    // MARK: - The one plain reason

    /// A draft on its way to being a position is not a mistake to report, and
    /// this is where that is decided. The core answers a board short of a
    /// general under its count clause, naming the side; what makes it this
    /// verdict rather than a violation to fix is the draft's own material —
    /// the piece the count is short of is still in the palette.
    @Test("Until both generals stand, the reason is the generals")
    func theMissingGeneralIsTheCountClause() throws {
        let core = try TestCores.fresh()
        let scene = CustomScene(core: core)
        #expect(scene.verdict == .incomplete, "an empty board has neither general")
        #expect(!scene.canStart)

        try place(scene, [("e1", Self.red(.general))])
        #expect(scene.verdict == .incomplete, "and one general is still not both")

        try place(scene, [("d10", Self.black(.general))])
        #expect(scene.verdict == .startable)
    }

    /// One position per class the editor can be shown, because the classes are
    /// the axis the copy is keyed on: a mapping that named the wrong one would
    /// tell a player to fix something that is not wrong.
    ///
    /// **The classes reach the page two ways, and each is asked here the way it
    /// arrives.** The two that are about the whole position stand in the
    /// verdict, because the piece that makes them true still lands. The three
    /// that are about where one piece may stand never become a verdict at all —
    /// the point refuses the piece — so they are read off the refusal, whose
    /// sentence is the same sentence the verdict would have carried.
    @Test("Each refusal the core makes is carried as its own class, side and point")
    func eachRefusalIsCarriedAsItsOwnClass() throws {
        let core = try TestCores.fresh()

        func verdict(of pieces: [(String, Piece)],
                     sideToMove: Side = .red) throws -> CustomScene.Verdict {
            let scene = CustomScene(core: core)
            scene.sideToMove = sideToMove
            try place(scene, pieces)
            return scene.verdict
        }

        /// What a point says back when it will not take the piece offered to
        /// it, over a board that already has its two generals.
        func refusal(of piece: Piece, at name: String) throws -> String? {
            let scene = CustomScene(core: core)
            try generals(scene)
            scene.pick(piece)
            scene.tap(try square(name))
            return scene.refusal?.reason
        }

        /// The sentence one class, side and point comes to.
        func sentence(_ rule: SetupRule, _ side: Side?, _ square: String) -> String? {
            CustomScene.Verdict
                .violation(SetupViolation(rule: rule, side: side, square: square))
                .reason
        }

        #expect(try verdict(of: [("e1", Self.red(.general)),
                                 ("e10", Self.black(.general))])
                == .violation(SetupViolation(rule: .facingGenerals, side: nil, square: "")),
                "the relation belongs to neither side and names no point")

        #expect(try verdict(of: [("e1", Self.red(.general)),
                                 ("d10", Self.black(.general)),
                                 ("e10", Self.black(.chariot))],
                            sideToMove: .black)
                == .violation(SetupViolation(rule: .opponentInCheck, side: .red,
                                             square: "e1")),
                "the side not to move is the one that may not be in check")

        // One class covers the general and the advisor, whose points differ, so
        // an advisor's refusal is carried by the sentence that is true of every
        // point it is refused at rather than by the palace's.
        #expect(try refusal(of: Self.red(.advisor), at: "c1")
                == SetupViolation(rule: .palace, side: .red, square: "c1")
                    .reason(refusing: .advisor))

        #expect(try refusal(of: Self.red(.elephant), at: "f1")
                == sentence(.elephantSide, .red, "f1"))

        #expect(try refusal(of: Self.red(.soldier), at: "g1")
                == sentence(.soldierRank, .red, "g1"))
    }

    /// The three findings the point clauses' exactness turns into behaviour.
    ///
    /// Not a sweep of the board: the clauses themselves are pinned by the
    /// fixtures, and these are the places where being exact changes what a tap
    /// does. Each is one refusal against the point that does take the piece.
    @Test("A point off the piece's own points refuses it, generals or no generals")
    func theZoneClausesAnswerFromTheFirstPieceDown() throws {
        let core = try TestCores.fresh()

        // On an empty board, before either general is placed: the classes that
        // name a point are reported ahead of the one that counts a side, so the
        // page answers the first piece put down.
        let empty = CustomScene(core: core)
        empty.pick(Self.red(.advisor))
        empty.tap(try square("e3"))
        let refused = try #require(empty.refusal, "the point answered over an empty board")
        #expect(refused.reason
                == SetupViolation(rule: .palace, side: .red, square: "e3")
                    .reason(refusing: .advisor))
        #expect(empty.pieces.isEmpty, "and nothing was placed")

        // An advisor steps diagonally, so the palace's four corners and its
        // centre are the whole of where it can be — e3 is inside the palace and
        // is none of them.
        let advisors = CustomScene(core: core)
        try generals(advisors)
        advisors.pick(Self.red(.advisor))
        advisors.tap(try square("e3"))
        #expect(advisors.pieces[try square("e3")] == nil, "a midpoint is not one of the five")
        advisors.tap(try square("d1"))
        #expect(advisors.pieces[try square("d1")] == Self.red(.advisor), "a corner is")
        advisors.tap(try square("e2"))
        #expect(advisors.pieces[try square("e2")] == Self.red(.advisor), "and so is the centre")

        // A soldier that has not crossed the river moves only forward, so it
        // stands on a file its side's soldiers start on; across the river every
        // file is one it may stand on.
        let soldiers = CustomScene(core: core)
        try generals(soldiers)
        soldiers.pick(Self.red(.soldier))
        soldiers.tap(try square("b4"))
        #expect(soldiers.pieces[try square("b4")] == nil,
                "b is not a file Red's soldiers start on")
        soldiers.tap(try square("b6"))
        #expect(soldiers.pieces[try square("b6")] == Self.red(.soldier),
                "and the same soldier across the river stands on it")
    }

    @Test("Every reason the editor can show is a sentence, and the startable one is none")
    func everyReasonIsASentence() throws {
        let core = try TestCores.fresh()
        let scene = CustomScene(core: core)
        #expect(scene.verdict.reason != nil, "an empty board says what to do about it")

        try generals(scene)
        #expect(scene.verdict == .startable)
        #expect(scene.verdict.reason == nil, "and a position to start from says nothing")

        // Every class the editor can be shown has a sentence of its own. What
        // those sentences say is the catalog's, and CopyTests is where both
        // languages are held to answering for them.
        for rule in [SetupRule.pieceCount, .palace, .elephantSide, .soldierRank,
                     .facingGenerals, .opponentInCheck] {
            let violation = SetupViolation(rule: rule, side: .red, square: "e1")
            #expect(CustomScene.Verdict.violation(violation).reason != nil,
                    "\(rule) has copy of its own")
        }
        #expect(CustomScene.Verdict.decided.reason != nil)
    }

    // MARK: - Legal is not the same as playable

    @Test("A legal position that is already decided is not one to start from")
    func aDecidedPositionIsNotAScene() throws {
        let core = try TestCores.fresh()
        let scene = CustomScene(core: core)
        scene.sideToMove = .black
        try place(scene, [("e1", Self.red(.general)), ("d10", Self.black(.general)),
                          ("d1", Self.red(.chariot)), ("e2", Self.red(.chariot))])
        #expect(scene.fen == Self.decidedScene)

        #expect(core.setupVerdict(of: scene.fen, game: .xiangqi) == .legal,
                "the predicate accepts it: startability is not its question")
        #expect(scene.verdict == .decided)
        #expect(!scene.canStart, "and 开始对局 is enabled on nothing else")

        // Which is the whole reason the second question is asked: creation
        // refuses exactly this position, and a Start that offered it would be
        // offering an error.
        #expect(throws: CoreError.self) {
            try core.create(.freePlay(game: .xiangqi, startFEN: scene.fen))
        }
    }

    // MARK: - The game the editor starts

    @Test("开始对局 creates a Free Play game of Xiangqi from the composed position")
    func startingTheSceneCreatesTheFreePlayGame() throws {
        let core = try TestCores.fresh()
        let state = PlayState(core: core)
        state.startIfNeeded(policy: MotionPolicy(reduceMotion: true))
        state.chooseCustomScene()
        let scene = try #require(state.scene, "the row opens the editor")
        #expect(state.page == .customScene)

        scene.sideToMove = .black
        try generals(scene)
        state.startScene(policy: MotionPolicy(reduceMotion: true))

        #expect(state.page == .board, "and the board opens on it")
        #expect(state.scene == nil, "the draft became a game and is no longer a draft")
        let game = try #require(state.game)
        #expect(game.mode == .freePlay, "a Free Play game that began elsewhere")
        #expect(game.kind == .xiangqi)
        #expect(game.configuration.startFEN == Self.bareScene,
                "which carries the composed position as its start")
        #expect(game.evaluation.sideToMove == .black)
        #expect(game.firstMover == .black, "Black makes ply 0")
        #expect(!game.canResign, "Free Play has no opponent to resign to")
    }

    @Test("Leaving the editor discards the draft and creates nothing")
    func leavingTheEditorDiscardsTheDraft() throws {
        let core = try TestCores.fresh()
        let state = PlayState(core: core)
        state.startIfNeeded(policy: MotionPolicy(reduceMotion: true))
        state.chooseCustomScene()
        try generals(try #require(state.scene))

        state.leaveTopPage()

        #expect(state.page == .home)
        #expect(state.scene == nil, "the draft was only ever in memory")
        #expect(try !core.activeGameExists(), "and nothing was created on the way out")
        #expect(state.activeSummary == nil)

        // A second entry is a fresh draft rather than the one that was left.
        state.chooseCustomScene()
        #expect(try #require(state.scene).pieces.isEmpty)
    }

    @Test("With a game active the row confirms first, and the editor opens after the archive")
    func theRowIsAGameAndModeEntry() throws {
        let core = try TestCores.fresh()
        let archive = ParkedArchive(core)
        let state = PlayState(core: core, rules: archive)
        try core.create(.freePlay(game: .miniXiangqi))
        state.startIfNeeded(policy: MotionPolicy(reduceMotion: true))

        state.chooseCustomScene()

        #expect(state.modeSwitch == .confirming(PlaySelection(game: .xiangqi,
                                                              mode: .freePlay)),
                "the accepted confirmation, over what the scene will create")
        #expect(state.page == .home, "and nothing opens until the archive commits")
        #expect(state.scene == nil)

        state.saveAndContinue()
        archive.answer(.success(1))

        #expect(state.page == .customScene, "the editor, and not a Free Play pre-start")
        #expect(state.scene != nil)
    }

    /// The one draft the editor can carry to a control that would be refused:
    /// a position the predicate accepts and creation does not. 开始对局 is
    /// disabled on it, and the flow refuses it for the same reason rather than
    /// reaching creation and reporting the refusal as a game that could not be
    /// saved.
    @Test("A draft that is not startable never reaches creation")
    func anUnstartableDraftNeverReachesCreation() throws {
        let core = try TestCores.fresh()
        let state = PlayState(core: core)
        state.startIfNeeded(policy: MotionPolicy(reduceMotion: true))
        state.chooseCustomScene()
        let scene = try #require(state.scene)
        scene.sideToMove = .black
        try place(scene, [("e1", Self.red(.general)), ("d10", Self.black(.general)),
                          ("d1", Self.red(.chariot)), ("e2", Self.red(.chariot))])
        #expect(scene.verdict == .decided, "which is why the control is disabled")

        state.startScene(policy: MotionPolicy(reduceMotion: true))

        #expect(state.page == .customScene, "the page and the draft stay")
        #expect(state.scene === scene)
        #expect(state.game == nil, "no game was created")
        #expect(try !core.activeGameExists())
        #expect(!state.creating, "and 开始对局 is on offer again")
        #expect(state.creationFailure == nil,
                "nothing failed: the position was never offered to the core")

        // And the same flow starts the moment the draft becomes one to play:
        // taking the checking chariot off leaves Black a move to make.
        scene.tap(try square("d1"))
        #expect(scene.canStart)
        state.startScene(policy: MotionPolicy(reduceMotion: true))
        #expect(state.page == .board)
    }
}

// MARK: - The configuration the start rides on

@Suite("A game's start position, across the interface", .retiringItsCores)
@MainActor
struct GameStartConfigurationTests {

    private static let scene = "3k5/9/9/9/9/9/9/9/9/4K4 b - - 0 1"

    @Test("A composed start survives the round trip, and a frozen one reads back absent")
    func theStartIsCanonicalAcrossTheRoundTrip() throws {
        let core = try TestCores.fresh()

        try core.create(.freePlay(game: .xiangqi, startFEN: Self.scene))
        #expect(try core.configuration().startFEN == Self.scene,
                "the composed start comes back exactly as it went in")
        core.endSession()

        // The frozen start spelled out is not a composed start anywhere in this
        // interface: the core makes the member canonical, and the mirror keeps
        // that answer rather than reporting the position back.
        let other = try TestCores.fresh()
        try other.create(.freePlay(game: .xiangqi,
                                   startFEN: Core.startFEN(for: .xiangqi)))
        #expect(try other.configuration().startFEN == nil)

        let plain = try TestCores.fresh()
        try plain.create(.freePlay(game: .xiangqi))
        #expect(try plain.configuration().startFEN == nil)
    }

    @Test("A start is Free Play's alone, and Xiangqi's alone")
    func theStartAxisIsRefusedWhereItIsMeaningless() throws {
        let core = try TestCores.fresh()

        // Mini Xiangqi defines no setup-legality predicate, so it begins from
        // its frozen start and from no other position.
        #expect(throws: CoreError.self) {
            try core.create(.freePlay(game: .miniXiangqi, startFEN: Self.scene))
        }
        #expect(try !core.activeGameExists(), "and a refused creation creates nothing")
    }

    @Test("The home reads whose turn it is from the core, not from the ply count")
    func theActiveSummaryCarriesTheCoresOwnSide() throws {
        let core = try TestCores.fresh()
        try core.create(.freePlay(game: .xiangqi, startFEN: Self.scene))
        core.endSession()

        let summary = try #require(try core.activeGameSummary())
        #expect(summary.moveCount == 0)
        #expect(summary.sideToMove == .black,
                "a game whose start has Black to move has Black making ply 0")
        #expect(summary.mode == .freePlay)
        #expect(summary.game == .xiangqi)
    }
}

// MARK: - Either first mover

/// The move list's pairing and numbering, and the Play home's side-to-move
/// line, for a game that did not open with Red.
///
/// Both exist because a scene may open with Black. What they catch is the
/// derivation they replaced: a mover taken from a ply's parity, which is right
/// for every game the app could make before this campaign and wrong for every
/// Black-first one it can make now.
@Suite("A game either side opened", .retiringItsCores)
@MainActor
struct FirstMoverTests {

    private static let blackFirst = "3k5/9/9/9/9/9/9/9/9/4K4 b - - 0 1"

    @Test("A Red-first game pairs a ply with its answer, numbering from one")
    func aRedFirstGamePairsAsItAlwaysDid() {
        let pairing = MovePairing(plies: 3, firstMover: .red)
        #expect(pairing.rows == [MovePairing.Row(number: 1, red: 0, black: 1),
                                 MovePairing.Row(number: 2, red: 2, black: nil)])
        #expect(pairing.row(of: 0) == 1)
        #expect(pairing.row(of: 2) == 2)
        #expect(MovePairing(plies: 0, firstMover: .red).rows.isEmpty)
    }

    @Test("A Black-first game opens with an empty Red cell, numbered from its own first ply")
    func aBlackFirstGameOpensWithAnEmptyRedCell() {
        let pairing = MovePairing(plies: 3, firstMover: .black)
        #expect(pairing.rows == [MovePairing.Row(number: 1, red: nil, black: 0),
                                 MovePairing.Row(number: 2, red: 1, black: 2)])
        #expect(pairing.row(of: 0) == 1, "the first ply is in the first row either way")
        #expect(pairing.row(of: 1) == 2)
        #expect(MovePairing(plies: 1, firstMover: .black).rows
                == [MovePairing.Row(number: 1, red: nil, black: 0)])
    }

    @Test("A scene game's own plies pair from the side its start had to move")
    func aSceneGamePairsFromItsOwnStart() throws {
        let core = try TestCores.fresh()
        try core.create(.freePlay(game: .xiangqi, startFEN: Self.blackFirst))
        let game = try Game(rules: core)
        #expect(game.firstMover == .black)

        try game.replay(["d10d9", "e1e2"])

        let pairing = MovePairing(plies: game.notation.count, firstMover: game.firstMover)
        #expect(pairing.rows == [MovePairing.Row(number: 1, red: nil, black: 0),
                                 MovePairing.Row(number: 2, red: 1, black: nil)],
                """
                Black's opening ply numbered 1 beside an empty Red cell, and \
                Red's answer opening the next row
                """)
    }

    @Test("A game from the frozen start still opens with Red")
    func aFrozenStartGameOpensWithRed() throws {
        let core = try TestCores.fresh()
        try core.create(.freePlay(game: .xiangqi))
        let game = try Game(rules: core)
        #expect(game.firstMover == .red)
    }
}
