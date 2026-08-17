// Jieqi, as the app plays it: the deal it begins from, the face-down piece the
// board carries, the reading the move list draws, and the surface that holds
// what a capture disclosed.
//
// Every expectation here is the core's own answer read back. Nothing asserts a
// rule: the deal is derived below the C interface, the legal moves are the
// core's, and what stands face down is what the position record says stands face
// down. What the suite pins is the app's side of it — that the record reaches
// the board whole, that what a player is entitled to know is what a surface can
// reach, and that the identity a face-down disc hides is nowhere a drawing or a
// label could find it.
//
// The two openings played through here are legal whatever the deal turns out to
// be, which is what makes them writable at all: a hidden piece moves as the
// piece whose square it stands on, so `b3b4` is a cannon's step for Red and
// `b8b1` is a cannon's shot for Black over the one screen that step left
// standing — and neither depends on what either piece turns up as.

import Foundation
import MiniXiangqiCore
import Testing
@testable import MiniXiangqi

@Suite("Jieqi", .retiringItsCores)
@MainActor
struct JieqiTests {

    private static let board = GameKind.jieqi.board

    private static func square(_ name: String) -> Square {
        Square(name, on: board)!
    }

    /// A Free Play game, created the way the Play destination creates one: the
    /// app draws the entropy, the core derives the deal, and the dealt start is
    /// what the game is created from.
    private func dealtGame(on core: Core) throws -> Game {
        let deal = try core.deal(.jieqi)
        try core.create(.freePlay(game: .jieqi, startFEN: deal.startFEN))
        return try Game(rules: core)
    }

    // MARK: - The deal

    @Test("A dealt start is a position the game begins from, and the record holds it")
    func theDealIsWhereTheGameBegins() throws {
        let core = try TestCores.fresh()

        #expect(Core.frozenStartFEN(for: .jieqi) == nil,
                "there is no frozen start to report: there is one for every deal")
        #expect(Core.frozenStartFEN(for: .xiangqi) != nil)

        let deal = try core.deal(.jieqi)
        #expect(core.setupVerdict(of: deal.startFEN, game: .jieqi) == .legal)
        #expect(core.isPlayable(deal.startFEN, game: .jieqi))
        // The two derived values are the spelling every handshake value has.
        #expect(deal.commit.count == 64)
        #expect(deal.digest.count == 64)
        #expect(deal.commit.allSatisfy { $0.isHexDigit && !$0.isUppercase })

        try core.create(.freePlay(game: .jieqi, startFEN: deal.startFEN))
        #expect(try core.configuration().startFEN == deal.startFEN,
                "a dealt start reads back spelled out: it is where this game began")
    }

    @Test("Only the dealt game deals, and every other game refuses")
    func onlyOneGameIsDealt() throws {
        let core = try TestCores.fresh()
        for game in GameKind.allCases where game != .jieqi {
            #expect(throws: CoreError.self) { try core.deal(game) }
        }
    }

    // MARK: - The board's vocabulary

    @Test("The dealt start reaches the board as face-down pieces of their squares' roles")
    func theBoardReadsTheDealtStart() throws {
        let core = try TestCores.fresh()
        let game = try dealtGame(on: core)

        let general = try #require(game.placement[Self.square("e1")])
        #expect(general.kind == .general)
        #expect(!general.isFaceDown, "the two generals are the only pieces that start face up")
        #expect(!(try #require(game.placement[Self.square("e10")])).isFaceDown)

        // A face-down piece carries the role its square gives it and never the
        // identity the position holds under it.
        let corner = try #require(game.placement[Self.square("a1")])
        #expect(corner.isFaceDown)
        #expect(corner.side == .red)
        #expect(corner.kind == .chariot, "a1 is a chariot's square, whatever stands on it")
        #expect((try #require(game.placement[Self.square("b3")])).kind == .cannon)
        #expect((try #require(game.placement[Self.square("c7")])).kind == .soldier)

        var faceDown = 0
        var occupied = 0
        for rank in 0..<Self.board.rankCount {
            for file in 0..<Self.board.fileCount {
                guard let piece = game.placement[Square(file: file, rank: rank)] else { continue }
                occupied += 1
                if piece.isFaceDown { faceDown += 1 }
            }
        }
        #expect(occupied == 32, "Xiangqi's thirty-two start squares, and no other point")
        #expect(faceDown == 30, "every non-general piece is dealt face down")
    }

    @Test("What the record holds under the discs is one side's fifteen pieces, and is not the discs")
    func theConcealedIdentitiesAreTheSidesOwnPieces() throws {
        let core = try TestCores.fresh()
        let game = try dealtGame(on: core)

        var counted: [PieceKind: Int] = [:]
        for rank in 0..<Self.board.rankCount {
            for file in 0..<Self.board.fileCount {
                let square = Square(file: file, rank: rank)
                guard let piece = game.placement[square], piece.side == .red,
                      piece.isFaceDown else { continue }
                let identity = try #require(game.placement.concealedIdentity(at: square))
                counted[identity, default: 0] += 1
            }
        }
        #expect(counted == [.chariot: 2, .horse: 2, .elephant: 2, .advisor: 2,
                            .cannon: 2, .soldier: 5],
                "each side's fifteen face-down identities are that side's non-general pieces")
        // And a face-up point has nothing concealed under it.
        #expect(game.placement.concealedIdentity(at: Self.square("e1")) == nil)
        #expect(game.placement.concealedIdentity(at: Self.square("e5")) == nil)
    }

    // MARK: - The move list

    @Test("A face-down mover reads as its square's role, marked, with the reveal last")
    func theReadingMarksTheMoverAndSaysWhatItTurnedUp() throws {
        let core = try TestCores.fresh()
        let game = try dealtGame(on: core)

        game.tap(Self.square("b3"))
        game.tap(Self.square("b4"))
        #expect(game.moves == ["b3b4"], "the canonical notation is what is stored")

        let arrived = try #require(game.placement[Self.square("b4")])
        #expect(!arrived.isFaceDown, "a hidden piece flips on completing its move, always")

        let reading = try #require(game.notation.last)
        let revealed = WXFNotation.letter(try #require(arrived.kind))
        #expect(reading.wxf == "C~8+1:" + revealed)
        #expect(reading.traditional == reading.wxf,
                "one rendering, whichever way the 记谱法 preference stands")

        // Black's answer is the same shape from the other side's own file
        // numbering, and it captures.
        game.tap(Self.square("b8"))
        game.tap(Self.square("b1"))
        #expect(game.moves == ["b3b4", "b8b1"])
        let answered = try #require(game.notation.last)
        let black = WXFNotation.letter(try #require(game.placement[Self.square("b1")]?.kind))
        #expect(answered.wxf == "C~2+7:" + black)
    }

    @Test("A revealed piece's move is the ordinary reading, with no mark and nothing disclosed")
    func aRevealedMoveReadsAsItAlwaysDid() {
        // jq-mix-001's start position: one face-down piece on a chariot's
        // square, and everything else revealed.
        let placement = Placement(fen: "3c5/9/2n2k3/9/2N6/9/9/9/9/C~2K5 w - - 0 1",
                                  game: .jieqi)
        #expect(placement[Self.square("c8")]?.isFaceDown == false)

        let move = Move(text: "c8d6", on: Self.board)!
        let reading = MoveReading(of: move, in: placement, after: nil)
        #expect(reading.wxf == "H3+4")
        #expect(reading.traditional == reading.wxf)

        // And the face-down piece beside it is the role its square gives it —
        // a chariot's square holding a cannon.
        #expect(placement[Self.square("a1")]?.kind == .chariot)
        #expect(placement[Self.square("a1")]?.isFaceDown == true)
        #expect(placement.concealedIdentity(at: Self.square("a1")) == .cannon)
    }

    // MARK: - The captured surface

    @Test("A capture stands in the surface, and who may see it is the disclosure rule")
    func theCapturedSurfaceFollowsDisclosure() throws {
        let core = try TestCores.fresh()
        let game = try dealtGame(on: core)
        let identity = try #require(game.placement.concealedIdentity(at: Self.square("b1")))

        #expect(game.captured.isEmpty, "nothing has been taken yet")

        game.tap(Self.square("b3"))
        game.tap(Self.square("b4"))
        game.tap(Self.square("b8"))
        game.tap(Self.square("b1"))

        let taken = try #require(game.captured.taken.first)
        #expect(game.captured.taken.count == 1)
        #expect(taken.side == .red, "Red is who lost the piece")
        #expect(taken.wasFaceDown, "it left the board face down, as a hidden piece does")
        #expect(taken.kind == identity, "and what it was is what the record held under it")

        let ply = game.moves.count
        // Free Play: one person holds both hands, so every disclosure is theirs
        // and nothing is ever a count.
        let free = game.captured.panel(of: .red, throughPly: ply, seenBy: nil,
                                       disclosed: false)
        #expect(free.pieces == [Piece(kind: identity, side: .red)])
        #expect(free.hidden == 0)

        // Its owner learns only that a piece is gone.
        let owner = game.captured.panel(of: .red, throughPly: ply, seenBy: .red,
                                        disclosed: false)
        #expect(owner.pieces.isEmpty)
        #expect(owner.hidden == 1)

        // Its capturer is shown it whole, because the capture disclosed it to
        // them alone.
        let capturer = game.captured.panel(of: .red, throughPly: ply, seenBy: .black,
                                           disclosed: false)
        #expect(capturer.pieces == [Piece(kind: identity, side: .red)])
        #expect(capturer.hidden == 0)

        // The end of the game discloses everything to both players, so the
        // count resolves into the piece it was counting.
        let ended = game.captured.panel(of: .red, throughPly: ply, seenBy: .red,
                                        disclosed: true)
        #expect(ended.pieces == [Piece(kind: identity, side: .red)])
        #expect(ended.hidden == 0)

        // And the surface follows the walk: before the ply that took it, it
        // holds nothing.
        #expect(game.captured.panel(of: .red, throughPly: 1, seenBy: nil,
                                    disclosed: false).pieces.isEmpty)
        // Black has lost nothing at all.
        #expect(game.captured.panel(of: .black, throughPly: ply, seenBy: nil,
                                    disclosed: false) ==
                CapturedPieces.Panel(side: .black, pieces: [], hidden: 0))
    }

    @Test("A retraction returns the concealment, and takes back what the ply took")
    func retractionReturnsBoth() throws {
        let core = try TestCores.fresh()
        let game = try dealtGame(on: core)

        game.tap(Self.square("b3"))
        game.tap(Self.square("b4"))
        game.tap(Self.square("b8"))
        game.tap(Self.square("b1"))
        #expect(game.captured.taken.count == 1)

        game.undo()
        #expect(game.moves == ["b3b4"])
        #expect(game.captured.isEmpty, "the piece that ply took is back on the board")
        #expect(game.placement[Self.square("b8")]?.isFaceDown == true,
                "and the piece that took it stands face down again")
        #expect(game.notation.count == 1)

        game.undo()
        #expect(game.moves.isEmpty)
        #expect(game.placement[Self.square("b3")]?.isFaceDown == true)
        #expect(game.notation.isEmpty)
    }

    // MARK: - What the board draws

    @Test("A revealing move travels as one disc carrying both faces")
    func theRevealRidesTheOneDisc() throws {
        let core = try TestCores.fresh()
        let game = try dealtGame(on: core)
        let animator = ManualAnimator()
        let motion = PlayMotion(game: game,
                                policy: MotionPolicy(reduceMotion: false),
                                animator: animator.animator,
                                feedback: try FeedbackRecorder(
                                    defaults: ScratchDefaults.make()).feedback)

        motion.tap(Self.square("b3"))
        motion.tap(Self.square("b4"))

        let transit = try #require(motion.transit)
        #expect(transit.piece.isFaceDown, "it left the board face down")
        #expect(transit.piece.kind == .cannon, "moving as the piece whose square it is")
        let revealed = try #require(transit.revealed)
        #expect(!revealed.isFaceDown, "and arrives face up")
        #expect(revealed.kind == game.placement[Self.square("b4")]?.kind,
                "as whatever the position it produced says it is")
        #expect(revealed.side == .red)

        animator.completeAll()
        #expect(motion.transit == nil)
        #expect(motion.transitReveal == 0, "the reveal is over with the transition")
        ScratchDefaults.clear()
    }

    @Test("An ordinary move carries no second face")
    func nothingElseReveals() throws {
        let core = try TestCores.fresh()
        let animator = ManualAnimator()
        let game = try openGame(on: core)
        let motion = PlayMotion(game: game,
                                policy: MotionPolicy(reduceMotion: false),
                                animator: animator.animator,
                                feedback: try FeedbackRecorder(
                                    defaults: ScratchDefaults.make()).feedback)
        motion.tap(Square("b1", on: GameKind.miniXiangqi.board)!)
        motion.tap(Square("b4", on: GameKind.miniXiangqi.board)!)
        #expect(motion.transit?.revealed == nil)
        animator.completeAll()
        ScratchDefaults.clear()
    }

    // MARK: - What the game does not carry

    @Test("No engine plays it, so there is no hint to offer and no AI to play")
    func theCapabilitiesThatAreNotThere() throws {
        #expect(!Core.isPlayedByAnEngine(.jieqi))
        #expect(GameKind.allCases.filter { !Core.isPlayedByAnEngine($0) } == [.jieqi])

        let core = try TestCores.fresh()
        let state = PlayState(core: core, engine: TestEngine())
        state.choose(PlaySelection(game: .jieqi, mode: .freePlay))
        #expect(state.page == .setup(PlaySelection(game: .jieqi, mode: .freePlay)))
        #expect(!state.preview.isEmpty,
                "the pre-start page previews a deal, every deal looking the same from outside")

        state.startGame(policy: MotionPolicy(reduceMotion: true))
        let game = try #require(state.game)
        #expect(state.page == .board)
        #expect(game.kind == .jieqi)
        #expect(game.mode == .freePlay)
        #expect(game.configuration.startFEN != nil, "created from the deal it drew")
        #expect(state.hint == nil,
                "a game no engine plays offers no hint: the capability is not there")
        #expect(!game.searchExpected, "and no search is ever owed")
    }

    @Test("Two deals are two games")
    func theDealIsDrawnAfresh() throws {
        let core = try TestCores.fresh()
        // The entropy is drawn per deal, so two deals of the same core are two
        // positions. Equal starts would mean the app dealt from a constant,
        // which is the one thing this call must never do; that they differ is
        // certain to within one chance in 15!².
        let first = try core.deal(.jieqi)
        let second = try core.deal(.jieqi)
        #expect(first.startFEN != second.startFEN)
        #expect(first.commit != second.commit)
        #expect(first.digest != second.digest)
    }
}
