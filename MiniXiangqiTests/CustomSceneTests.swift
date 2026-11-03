import Foundation
import MiniXiangqiCore
import Testing
@testable import MiniXiangqi

@Suite("The Custom Scene editor", .retiringItsCores)
@MainActor
struct CustomSceneTests {
    private static let board = CustomScene.game.board

    private static let bareScene = "3k5/9/9/9/9/9/9/9/9/4K4 b - - 0 1"

    private static let decidedScene = "3k5/9/9/9/9/9/9/9/4R4/3RK4 b - - 0 1"

    private func square(_ name: String) throws -> Square {
        try #require(Square(name, on: Self.board), "\(name) is a point of this board")
    }

    private func place(_ scene: CustomScene, _ pieces: [(String, Piece)]) throws {
        for (name, piece) in pieces {
            scene.pick(piece)
            scene.tap(try square(name))
        }
    }

    private static func red(_ kind: PieceKind) -> Piece { Piece(kind: kind, side: .red) }
    private static func black(_ kind: PieceKind) -> Piece { Piece(kind: kind, side: .black) }

    private func generals(_ scene: CustomScene) throws {
        try place(scene, [("e1", Self.red(.general)), ("d10", Self.black(.general))])
    }

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
        let start = Placement(fen: frozenStart(CustomScene.game),
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

        scene.tap(try square("d1"))
        #expect(scene.pieces[try square("d1")] == advisor)
        #expect(scene.refusal == nil)
    }

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

        func refusal(of piece: Piece, at name: String) throws -> String? {
            let scene = CustomScene(core: core)
            try generals(scene)
            scene.pick(piece)
            scene.tap(try square(name))
            return scene.refusal?.reason
        }

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

        #expect(try refusal(of: Self.red(.advisor), at: "c1")
                == SetupViolation(rule: .palace, side: .red, square: "c1")
                    .reason(refusing: .advisor))

        #expect(try refusal(of: Self.red(.elephant), at: "f1")
                == sentence(.elephantSide, .red, "f1"))

        #expect(try refusal(of: Self.red(.soldier), at: "g1")
                == sentence(.soldierRank, .red, "g1"))
    }

    @Test("A point off the piece's own points refuses it, generals or no generals")
    func theZoneClausesAnswerFromTheFirstPieceDown() throws {
        let core = try TestCores.fresh()

        let empty = CustomScene(core: core)
        empty.pick(Self.red(.advisor))
        empty.tap(try square("e3"))
        let refused = try #require(empty.refusal, "the point answered over an empty board")
        #expect(refused.reason
                == SetupViolation(rule: .palace, side: .red, square: "e3")
                    .reason(refusing: .advisor))
        #expect(empty.pieces.isEmpty, "and nothing was placed")

        let advisors = CustomScene(core: core)
        try generals(advisors)
        advisors.pick(Self.red(.advisor))
        advisors.tap(try square("e3"))
        #expect(advisors.pieces[try square("e3")] == nil, "a midpoint is not one of the five")
        advisors.tap(try square("d1"))
        #expect(advisors.pieces[try square("d1")] == Self.red(.advisor), "a corner is")
        advisors.tap(try square("e2"))
        #expect(advisors.pieces[try square("e2")] == Self.red(.advisor), "and so is the centre")

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

        #expect(throws: CoreError.self) {
            try core.create(.freePlay(game: .xiangqi, startFEN: scene.fen))
        }
    }

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

        state.chooseCustomScene()
        #expect(try #require(state.scene).pieces.isEmpty)
    }

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

        scene.tap(try square("d1"))
        #expect(scene.canStart)
        state.startScene(policy: MotionPolicy(reduceMotion: true))
        #expect(state.page == .board)
    }
}

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

        let other = try TestCores.fresh()
        try other.create(.freePlay(game: .xiangqi,
                                   startFEN: frozenStart(.xiangqi)))
        #expect(try other.configuration().startFEN == nil)

        let plain = try TestCores.fresh()
        try plain.create(.freePlay(game: .xiangqi))
        #expect(try plain.configuration().startFEN == nil)
    }

    @Test("A start is Free Play's alone, and Xiangqi's alone")
    func theStartAxisIsRefusedWhereItIsMeaningless() throws {
        let core = try TestCores.fresh()

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
        let game = try Game(core: core)
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
        let game = try Game(core: core)
        #expect(game.firstMover == .red)
    }
}
