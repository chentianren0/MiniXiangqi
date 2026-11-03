import Foundation
import MiniXiangqiCore
import Testing
@testable import MiniXiangqi

@Suite("The persistent game", .retiringItsCores)
@MainActor
struct GameSessionTests {
    @Test("An untouched board persists nothing; 开始对局 is what creates the game")
    func startingTheGameCreatesIt() throws {
        let library = try TestLibraries.fresh()

        #expect(try library.activeRecord() == nil,
                "opening the app is not starting a game")
        #expect(!library.hasSession, "nothing is held either: there is nothing to hold")

        try library.create(.freePlay(game: .miniXiangqi))
        let game = try Game(library: library)

        #expect(library.hasSession)
        #expect(try library.activeRecord() != nil, "the game exists before its first move")
        #expect(game.moves.isEmpty, "and has no moves in it")
        #expect(game.kind == .miniXiangqi)
        #expect(game.mode == .freePlay)
        #expect(game.humanSide == nil, "Free Play has no human side: one person plays both")

        game.tap(Square("b1", on: GameKind.miniXiangqi.board)!)
        game.tap(Square("b4", on: GameKind.miniXiangqi.board)!)
        #expect(game.moves == ["b1b4"])
    }

    @Test("A created human-versus-AI game keeps its side, level and thinking time")
    func creationFreezesTheConfiguration() throws {
        let library = try TestLibraries.fresh()
        try library.create(.humanVersusAI(game: .miniXiangqi, humanSide: .black, level: .deep))
        let game = try Game(library: library)

        let configuration = game.configuration
        #expect(configuration.game == .miniXiangqi)
        #expect(configuration.mode == .humanVersusAI)
        #expect(configuration.humanSide == .black,
                "the resolved side, not the choice that produced it")
        #expect(configuration.aiLevel == .deep)
        #expect(configuration.movetimeMilliseconds == 5000,
                "深思 is go movetime 5000")
        #expect(game.humanSide == .black)
        #expect(game.flipped,
                "the human's own side is at the bottom, so a Black human turns the board")
        #expect(game.searchExpected,
                "Red moves first and the human is Black, so the AI owes the opening move")
        #expect(!game.canResign == false, "resignation is on offer in human-versus-AI play")
    }

    @Test("Every game is created as the game it was asked for", arguments: GameKind.allCases)
    func gameKindSurvivesConfiguration(_ kind: GameKind) throws {
        let library = try TestLibraries.fresh()
        let start = try Core.frozenStartFEN(for: kind) == nil
            ? library.core.deal(kind).startFEN : nil
        let configuration = GameConfiguration.freePlay(game: kind, startFEN: start)

        try library.create(configuration)
        #expect(try library.configuration() == configuration,
                "the record reports the game it was created for")
    }

    @Test("A Xiangqi game presents every legal move the core returns")
    func xiangqiLegalMovesAreNeverDroppedByPresentationParsing() throws {
        let library = try TestLibraries.fresh()
        try library.create(.freePlay(game: .xiangqi))

        let game = try Game(library: library)
        let canonical = try library.legalMoves()

        #expect(game.kind == .xiangqi)
        #expect(game.failure == nil)
        #expect(game.legalMoves.map(\.text) == canonical,
                "a canonical core move must not disappear in a compactMap")
        #expect(game.placement[Square("d1", on: GameKind.xiangqi.board)!]
                == Piece(kind: .advisor, side: .red))
        #expect(game.placement[Square("c10", on: GameKind.xiangqi.board)!]
                == Piece(kind: .elephant, side: .black))
    }

    @Test("A move is saved when it is accepted, and survives a relaunch of the container")
    func everyMoveCommits() throws {
        let url = TestLibraries.scratchURL()
        let library = try TestLibraries.open(at: url)
        let game = try openGame(on: library)
        try game.replay(["b1b4", "a6a5"])

        let relaunched = try TestLibraries.open(at: url, core: library.core)
        let resumed = try openGame(on: relaunched)
        #expect(resumed.moves == ["b1b4", "a6a5"],
                "both plies were saved as they were played")
    }

    @Test("A stored game resumes exactly: position, history, notation, turn")
    func aStoredGameResumesExactly() throws {
        let url = TestLibraries.scratchURL()
        let library = try TestLibraries.open(at: url)
        let played = try openGame(on: library)
        try played.replay(GameTests.captureLine)
        let fen = played.evaluation.fen
        let notation = played.notation
        #expect(notation.map(\.traditional) == ["兵四进一", "卒4进1", "兵四进一", "卒4进1"],
                "the premise: the sitting recorded these words")
        #expect(notation.map(\.wxf) == ["P4+1", "P4+1", "P4+1", "P4+1"],
                "and these, since a resumed game has to read the same in either")

        let relaunched = try TestLibraries.open(at: url, core: library.core)
        let resumed = try openGame(on: relaunched)

        #expect(resumed.moves == GameTests.captureLine)
        #expect(resumed.evaluation.fen == fen, "the position is the same position")
        #expect(resumed.notation == notation,
                "the notation reads back through the same rules that wrote it")
        #expect(resumed.lastMove == Move(text: "d5d4", on: GameKind.miniXiangqi.board),
                "the brackets mark the move that produced the position")
        #expect(resumed.evaluation.sideToMove == .red)
        #expect(resumed.canUndo, "the resumed game is the same game to play on")
        #expect(!resumed.flipped,
                "orientation is the sitting's, not the game's: a fresh launch opens red-at-bottom")
    }

    static let longLine = [
        "a2a3", "a6a5", "c2c3", "c6c5", "d2d3", "d6d5", "e2e3", "e6e5",
        "g2g3", "g6g5", "c1b3", "c7b5", "e1f3", "e7f5", "a1a2", "a7a6",
        "g1g2", "g7g6", "f1f2", "f7f6", "b1b2", "b7b6",
        "a2a1", "a6a7", "a1a2", "a7a6", "a2a1", "a6a7", "a1a2", "a7a6",
        "a2a1", "a6a7", "a1a2", "a7a6", "a2a1", "a6a7", "a1a2", "a7a6",
        "a2a1", "a6a7",
    ]

    @Test("A forty-ply game resumes whole: every ply, every word, the same position")
    func aLongGameResumesWhole() throws {
        let url = TestLibraries.scratchURL()
        let library = try TestLibraries.open(at: url)
        let played = try openGame(on: library)
        try played.replay(Self.longLine)
        #expect(played.moves.count == 40, "the premise: forty plies were committed")
        let fen = played.evaluation.fen
        let notation = played.notation

        let relaunched = try TestLibraries.open(at: url, core: library.core)
        let resumed = try openGame(on: relaunched)

        #expect(resumed.moves == Self.longLine, "the whole line came back")
        #expect(resumed.notation == notation, "and reads in the same forty words")
        #expect(resumed.evaluation.fen == fen)
        #expect(resumed.lastMove == Move(text: "a6a7", on: GameKind.miniXiangqi.board))
        #expect(resumed.evaluation.claimAvailable,
                "the repetition the line ends on is still on offer")
        #expect(!resumed.isFinished, "and a claimable repetition is not an ending")
    }

    @Test("Two finished games make two History records, newest first")
    func twoGamesFileIntoOneStore() throws {
        let library = try TestLibraries.fresh()

        let first = try openGame(on: library)
        try first.replay(GameTests.mateLine)
        try first.file()

        library.endSession()
        let second = try openGame(on: library)
        try second.replay(GameTests.shuffleLine)
        second.claimDraw()

        #expect(try library.history().count == 2, "one library, two games")
        #expect(try library.activeRecord() == nil, "and nothing left in play")
        #expect(first.filedRecordID != second.filedRecordID,
                "two records, not one written twice")
        #expect(try library.history().map(\.id) == [second.filedRecordID, first.filedRecordID],
                "the most recently ended first")
    }

    @Test("With nothing stored, PlayState stays home and Game cannot represent absence")
    func absenceStaysAtHome() throws {
        let library = try TestLibraries.fresh()
        #expect(throws: CoreError.self) { try Game(library: library) }

        let state = PlayState(library: library)
        state.startIfNeeded(policy: MotionPolicy(reduceMotion: true))

        #expect(state.started)
        #expect(state.page == .home)
        #expect(state.game == nil, "absence belongs to PlayState, not to a placeholder Game")
        #expect(!library.hasSession, "absence holds nothing")
        #expect(try library.activeRecord() == nil, "and creates nothing")
    }

    @Test("A launch describes the stored game without taking it up")
    func aStoredGameIsDescribedWithoutBeingOpened() throws {
        let url = TestLibraries.scratchURL()
        let library = try TestLibraries.open(at: url)
        let played = try openGame(on: library)
        try played.replay(["b1b3", "b7b6"])

        let relaunched = try TestLibraries.open(at: url, core: library.core)
        let state = PlayState(library: relaunched)
        state.startIfNeeded(policy: MotionPolicy(reduceMotion: true))

        #expect(state.page == .home, "a fresh launch is not an entry into the game")
        #expect(!relaunched.hasSession, "and holds nothing")
        #expect(state.game == nil, "there is no living game to hold")
        #expect(state.activeSummary?.moveCount == 2,
                "what the home has is the library's summary of the line it was left at")

        state.resume(policy: MotionPolicy(reduceMotion: true))
        #expect(state.page == .board, "and the card is the way in")
        #expect(relaunched.hasSession, "which is where the game is taken up")
        #expect(state.game?.moves == ["b1b3", "b7b6"], "over the line it was left at")
    }

    @Test("An unconfirmed mate resumes finished, still undoable, and Undo resumes play")
    func anUnconfirmedResultResumesFinished() throws {
        let url = TestLibraries.scratchURL()
        let library = try TestLibraries.open(at: url)
        let mated = try openGame(on: library)
        try mated.replay(GameTests.mateLine)
        #expect(mated.isFinished)

        let relaunched = try TestLibraries.open(at: url, core: library.core)
        let resumed = try openGame(on: relaunched)

        #expect(resumed.isFinished, "the unconfirmed result is the game's state")
        #expect(resumed.presentedState == .redWins)
        #expect(resumed.evaluation.reason == .checkmate)
        #expect(resumed.canUndo, "unconfirmed is unconfirmed across a relaunch")

        resumed.undo()
        #expect(resumed.failure == nil, "the library saved the undo")
        #expect(!resumed.isFinished, "and the game is running again")
        #expect(resumed.moves == ["b1b3", "b7b6"])
    }

    @Test("Starting anew confirms the natural result into History and the next move creates fresh")
    func filingConfirmsTheResult() throws {
        let library = try TestLibraries.fresh()
        let game = try openGame(on: library)
        try game.replay(GameTests.mateLine)

        try game.file()
        #expect(game.filedRecordID != nil)
        #expect(try library.history().count == 1, "the finished game is a History record")
        #expect(try library.activeRecord() == nil, "and no longer the game in play")

        library.endSession()
        try library.create(.freePlay(game: .miniXiangqi))
        let next = try Game(library: library)
        #expect(next.moves.isEmpty)
        next.tap(Square("b1", on: GameKind.miniXiangqi.board)!)
        next.tap(Square("b4", on: GameKind.miniXiangqi.board)!)
        #expect(try library.activeRecord() != nil)
        #expect(try library.history().count == 1, "playing on files nothing further")
    }

    @Test("A saved result stands on its own board as a record, with nothing to undo")
    func savingLeavesTheGameOnTheRecordedBoard() throws {
        let library = try TestLibraries.fresh()
        let game = try openGame(on: library)
        try game.replay(GameTests.mateLine)
        #expect(game.canUndo, "the premise: an unconfirmed result is undoable")
        let mated = game.evaluation.fen

        try game.file()

        #expect(game.filedRecordID != nil, "the record exists")
        #expect(try library.history().count == 1)
        #expect(game.isFinished, "and the finished game is still the game on screen")
        #expect(game.presentedState == .redWins, "with the result it reached")
        #expect(game.evaluation.reason == .checkmate)
        #expect(game.moves == GameTests.mateLine, "nothing about the line changed")
        #expect(game.evaluation.fen == mated,
                "and the position is the mated position still")
        #expect(!game.canUndo,
                "what changed is the affordance: a History record is not undoable")
        #expect(game.failure == nil, "and the reads behind that answered")
        #expect(game.filingFailure == nil)
    }

    @Test("A game already filed is not filed a second time")
    func filingIsNotRepeated() throws {
        let library = try TestLibraries.fresh()
        let game = try openGame(on: library)
        try game.replay(GameTests.mateLine)

        try game.file()
        let record = game.filedRecordID

        try game.file()

        #expect(game.filedRecordID == record, "the same record, not a second one")
        #expect(try library.history().count == 1, "and one game is one record")
        #expect(game.filingFailure == nil, "nothing was refused, because nothing was asked")
    }

    @Test("A claimed draw needs no filing: the claim already was one")
    func aClaimedDrawIsAlreadyFiled() throws {
        let library = try TestLibraries.fresh()
        let game = try openGame(on: library)
        try game.replay(GameTests.shuffleLine)

        game.claimDraw()
        #expect(game.claimedDraw)
        #expect(try library.history().count == 1)

        try game.file()
        #expect(try library.history().count == 1,
                "filing a claimed draw commits nothing twice")
    }
}
