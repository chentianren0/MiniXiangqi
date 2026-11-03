import Foundation
import Testing
@testable import MiniXiangqi

@Suite("WXF notation")
@MainActor
struct WXFNotationTests {
    private func read(_ move: String, from fen: String,
                      game: GameKind = .miniXiangqi) -> String {
        WXFNotation.text(for: Move(text: move, on: game.board)!,
                         in: Placement(fen: fen, game: game))
    }

    private static let start = "rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1"

    private static let redLetters = "4k2/7/7/R2N2C/1P5/7/3K3 w - - 0 1"

    private static let blackLetters = "3k3/7/1p5/r2n2c/7/7/4K2 b - - 0 1"

    @Test("The piece letters are K, R, H, C and P, for both sides alike")
    func pieceLetters() {
        #expect(read("d1d2", from: Self.redLetters) == "K4+1")
        #expect(read("a4a7", from: Self.redLetters) == "R7+3")
        #expect(read("d4e6", from: Self.redLetters) == "H4+3")
        #expect(read("g4g7", from: Self.redLetters) == "C1+3")
        #expect(read("b3b4", from: Self.redLetters) == "P6+1")

        #expect(read("d7d6", from: Self.blackLetters) == "K4+1")
        #expect(read("a4a1", from: Self.blackLetters) == "R1+3")
        #expect(read("d4e2", from: Self.blackLetters) == "H4+5")
        #expect(read("g4g1", from: Self.blackLetters) == "C7+3")
        #expect(read("b5b4", from: Self.blackLetters) == "P2+1")
    }

    @Test("Xiangqi adds A and E and numbers all nine files")
    func xiangqiPieceLettersAndFiles() {
        let redAdvisor = "5k3/9/9/9/9/9/9/9/3K5/3A5 w - - 0 1"
        let redElephant = "5k3/9/9/9/9/9/9/9/3K5/2B6 w - - 0 1"
        let blackAdvisor = "3a1k3/9/9/9/9/9/9/9/9/3K5 b - - 0 1"
        let blackElephant = "2b2k3/9/9/9/9/9/9/9/9/3K5 b - - 0 1"
        let redEdges = "5k3/9/9/9/9/9/9/9/9/R2K4R w - - 0 1"
        let blackEdges = "r2k4r/9/9/9/9/9/9/9/9/5K3 b - - 0 1"

        #expect(read("d1e2", from: redAdvisor, game: .xiangqi) == "A6+5")
        #expect(read("c1e3", from: redElephant, game: .xiangqi) == "E7+5")
        #expect(read("d10e9", from: blackAdvisor, game: .xiangqi) == "A4+5")
        #expect(read("c10e8", from: blackElephant, game: .xiangqi) == "E3+5")
        #expect(read("a1a2", from: redEdges, game: .xiangqi) == "R9+1")
        #expect(read("i1i2", from: redEdges, game: .xiangqi) == "R1+1")
        #expect(read("a10a9", from: blackEdges, game: .xiangqi) == "R1+1")
        #expect(read("i10i9", from: blackEdges, game: .xiangqi) == "R9+1")
    }

    @Test("Xiangqi disambiguation scans the tenth rank")
    func xiangqiDisambiguationUsesTenRanks() {
        let fen = "R4k3/9/9/9/9/9/9/9/R8/3K5 w - - 0 1"
        #expect(read("a10b10", from: fen, game: .xiangqi) == "R+=8")
    }

    @Test("Red numbers files from its own right, in Arabic digits like Black")
    func redFileNumbering() {
        #expect(read("b3a3", from: Self.redLetters) == "P6=7")
        #expect(read("g4e4", from: Self.redLetters) == "C1=3")
        #expect(read("b1b3", from: Self.start) == "C6+2")
        #expect(read("f1f4", from: Self.start) == "C2+3")
    }

    @Test("Black numbers files from its own right, which is the other direction")
    func blackFileNumbering() {
        #expect(read("a4c4", from: Self.blackLetters) == "R1=3")
        #expect(read("g4e4", from: Self.blackLetters) == "C7=5")
        #expect(read("b5a5", from: Self.blackLetters) == "P2=1")
        #expect(read("a6a5", from: Self.start) == "P1+1")
    }

    @Test("The directions are + advance, - retreat and = traverse")
    func directions() {
        #expect(read("a4a7", from: Self.redLetters) == "R7+3")
        #expect(read("a4a1", from: Self.redLetters) == "R7-3")
        #expect(read("a4c4", from: Self.redLetters) == "R7=5")

        #expect(read("a4a1", from: Self.blackLetters) == "R1+3")
        #expect(read("a4a7", from: Self.blackLetters) == "R1-3")
        #expect(read("a4c4", from: Self.blackLetters) == "R1=3")
    }

    @Test("A move along its own file counts the ranks it crossed")
    func alongTheFileCountsRanks() {
        #expect(read("a4a7", from: Self.redLetters) == "R7+3")
        #expect(read("g4g7", from: Self.redLetters) == "C1+3")
        #expect(read("b3b4", from: Self.redLetters) == "P6+1")
        #expect(read("d1d2", from: Self.redLetters) == "K4+1")
    }

    @Test("A rank count is the distance, at every distance a chariot can travel",
          arguments: [("4k2/7/7/7/7/7/R2K3 w - - 0 1", "a1a5", "R7+4"),
                      ("4k2/7/7/7/7/7/R2K3 w - - 0 1", "a1a6", "R7+5"),
                      ("4k2/7/7/7/7/7/R2K3 w - - 0 1", "a1a7", "R7+6"),
                      ("R6/3k3/7/7/7/7/2K4 w - - 0 1", "a7a3", "R7-4"),
                      ("R6/3k3/7/7/7/7/2K4 w - - 0 1", "a7a2", "R7-5"),
                      ("R6/3k3/7/7/7/7/2K4 w - - 0 1", "a7a1", "R7-6")])
    func rankCountsReachTheWholeFile(fen: String, move: String, expected: String) {
        #expect(read(move, from: fen) == expected)
    }

    @Test("A move that leaves its file names the file it arrived on")
    func leavingTheFileNamesIt() {
        #expect(read("a4c4", from: Self.redLetters) == "R7=5")
        #expect(read("g4e4", from: Self.redLetters) == "C1=3")
        #expect(read("b3a3", from: Self.redLetters) == "P6=7")
        #expect(read("d1c1", from: Self.redLetters) == "K4=5")
    }

    @Test("A horse names its destination file after + or -, because it leaves its file",
          arguments: [("d4c6", "H4+5"), ("d4f5", "H4+2"),
                      ("d4e2", "H4-3"), ("d4c2", "H4-5"), ("d4f3", "H4-2")])
    func horseNamesItsDestinationFile(move: String, expected: String) {
        #expect(read(move, from: Self.redLetters) == expected)
    }

    @Test("The horse's file is Black's own when Black moves it",
          arguments: [("d4e2", "H4+5"), ("d4c2", "H4+3"),
                      ("d4e6", "H4-5"), ("d4f5", "H4-6")])
    func blackHorseNamesItsDestinationFile(move: String, expected: String) {
        #expect(read(move, from: Self.blackLetters) == expected)
    }

    private static let pairs = "2k4/7/1R3NC/7/7/1R3NC/3K3 w - - 0 1"

    @Test("With two on a file the marker replaces the file, AFTER the letter")
    func twoOnAFileTakeTheMarker() {
        #expect(read("b5c5", from: Self.pairs) == "R+=5")
        #expect(read("b2b3", from: Self.pairs) == "R-+1")
    }

    @Test("+ is the piece nearer the opponent and - the one nearer home",
          arguments: [("b5b6", "R++1"), ("b2a2", "R-=7"),
                      ("f5e7", "H++3"), ("f2e4", "H-+3"),
                      ("g5g6", "C++1"), ("g2g1", "C--1")])
    func markerIsRelativeToTheMover(move: String, expected: String) {
        #expect(read(move, from: Self.pairs) == expected)
    }

    @Test("A marked horse still names a file, and a marked cannon still counts ranks",
          arguments: [("f5g3", "H+-1"), ("f5d4", "H+-4"), ("f2g4", "H-+1"),
                      ("g5g4", "C+-1"), ("g2g3", "C-+1")])
    func markerLeavesTheValueAlone(move: String, expected: String) {
        #expect(read(move, from: Self.pairs) == expected)
    }

    private static let soldierPair = "4k2/7/1P5/7/1P5/7/3K3 w - - 0 1"

    @Test("A soldier pair takes the marker exactly as the other types do",
          arguments: [("b5b6", "P++1"), ("b3b4", "P-+1"),
                      ("b5c5", "P+=5"), ("b3a3", "P-=7")])
    func soldierPairTakesTheMarker(move: String, expected: String) {
        #expect(read(move, from: Self.soldierPair) == expected)
    }

    @Test("A pair keeps its marker when a third file carries only one",
          arguments: [("b5b6", "P++1"), ("b3b4", "P-+1"),
                      ("f3f4", "P2+1"), ("f3g3", "P2=1")])
    func aPairKeepsItsMarkerBesideALoneSingle(move: String, expected: String) {
        #expect(read(move, from: "4k2/7/1P5/7/1P3P1/7/3K3 w - - 0 1") == expected)
    }

    @Test("The marker is written whenever two stand on the file, not only when a move would be ambiguous")
    func theMarkerIsUnconditional() {
        let fen = "1P2k2/7/1P5/7/7/7/3K3 w - - 0 1"
        #expect(read("b5b6", from: fen) == "P-+1")
        #expect(MoveNotation.text(
            for: Move(text: "b5b6", on: GameKind.miniXiangqi.board)!,
            in: Placement(fen: fen, game: .miniXiangqi)) == "后兵进一")

        #expect(read("b7a7", from: fen) == "P+=7")
        #expect(read("b7c7", from: fen) == "P+=5")
        #expect(read("b5a5", from: fen) == "P-=7")
        #expect(read("b5c5", from: fen) == "P-=5")
    }

    @Test("Three on a file are indexed from the front, and the file stays",
          arguments: [("c6c7", "15+1"), ("c4c5", "25+1"), ("c2c3", "35+1"),
                      ("c6d6", "15=4"), ("c4b4", "25=6"), ("c2d2", "35=4")])
    func threeOnAFile(move: String, expected: String) {
        #expect(read(move, from: "4k2/2P4/7/2P4/7/2P4/3K3 w - - 0 1") == expected)
    }

    @Test("Four on a file, every index",
          arguments: [("c6d6", "15=4"), ("c5d5", "25=4"),
                      ("c4d4", "35=4"), ("c3d3", "45=4")])
    func fourOnAFile(move: String, expected: String) {
        #expect(read(move, from: "4k2/2P4/2P4/2P4/2P4/7/3K3 w - - 0 1") == expected)
    }

    @Test("Five on a file, every index — this board's maximum stack",
          arguments: [("c6d6", "15=4"), ("c5d5", "25=4"), ("c4d4", "35=4"),
                      ("c3d3", "45=4"), ("c2d2", "55=4")])
    func fiveOnAFile(move: String, expected: String) {
        #expect(read(move, from: "4k2/2P4/2P4/2P4/2P4/2P4/3K3 w - - 0 1") == expected)
    }

    @Test("With two files doubled every soldier on one is indexed within its own file")
    func twoDoubledFilesPromoteBothPairs() {
        let fen = "3k3/7/1P1P3/7/1P1P1P1/7/3K3 w - - 0 1"
        #expect(read("b5b6", from: fen) == "16+1")
        #expect(read("b3b4", from: fen) == "26+1")
        #expect(read("d5d6", from: fen) == "14+1")
        #expect(read("d3d4", from: fen) == "24+1")
        #expect(read("f3f4", from: fen) == "P2+1")
        #expect(read("f3g3", from: fen) == "P2=1")
        #expect(read("b5a5", from: fen) == "16=7")
        #expect(read("d5e5", from: fen) == "14=3")
    }

    @Test("Three and two across two files index each file separately")
    func threeTwoIndexesEachFile() {
        let fen = "3k3/7/1P1P3/7/1P1P3/7/1P1K3 w - - 0 1"
        #expect(read("b5b6", from: fen) == "16+1")
        #expect(read("b3b4", from: fen) == "26+1")
        #expect(read("b1b2", from: fen) == "36+1")
        #expect(read("d5d6", from: fen) == "14+1")
        #expect(read("d3d4", from: fen) == "24+1")
        #expect(read("b1a1", from: fen) == "36=7")
        #expect(read("b5a5", from: fen) == "16=7")
        #expect(read("d5c5", from: fen) == "14=5")
    }

    private static let blackPairs = "3k3/1r3nc/7/7/1r3nc/7/2K4 b - - 0 1"

    @Test("Black's pairs take the marker, front nearer Red",
          arguments: [("b3c3", "R+=3"), ("b3b2", "R++1"), ("b3b4", "R+-1"),
                      ("b6b5", "R-+1"), ("b6a6", "R-=1"),
                      ("f3e1", "H++5"), ("f3g1", "H++7"), ("f3d2", "H++4"),
                      ("f3d4", "H+-4"),
                      ("f6e4", "H-+5"), ("f6g4", "H-+7"), ("f6d5", "H-+4"),
                      ("g3g2", "C++1"), ("g3g4", "C+-1"),
                      ("g6g5", "C-+1"), ("g6g7", "C--1")])
    func blackPairsTakeTheMarker(move: String, expected: String) {
        #expect(read(move, from: Self.blackPairs) == expected)
    }

    @Test("Black's soldier pair, both markers and both directions",
          arguments: [("b3b2", "P++1"), ("b5b4", "P-+1"),
                      ("b3c3", "P+=3"), ("b5a5", "P-=1")])
    func blackSoldierPairTakesTheMarker(move: String, expected: String) {
        #expect(read(move, from: "3k3/7/1p5/7/1p5/7/4K2 b - - 0 1") == expected)
    }

    @Test("Black's marker is unconditional too, and on Red's back rank")
    func theMarkerIsUnconditionalForBlackToo() {
        let fen = "4k2/7/7/7/1p5/7/1p1K3 b - - 0 1"
        #expect(read("b3b2", from: fen) == "P-+1")
        #expect(MoveNotation.text(
            for: Move(text: "b3b2", on: GameKind.miniXiangqi.board)!,
            in: Placement(fen: fen, game: .miniXiangqi)) == "后卒进1")

        #expect(read("b1a1", from: fen) == "P+=1")
        #expect(read("b1c1", from: fen) == "P+=3")
        #expect(read("b3a3", from: fen) == "P-=1")
        #expect(read("b3c3", from: fen) == "P-=3")
    }

    @Test("Black's horse pair reaches the same divergence, retreating off the board")
    func blackHorseReachesTheSameDivergence() {
        #expect(read("f3g5", from: Self.blackPairs) == "H+-7")
    }

    @Test("Black's three on a file are indexed from Black's own front",
          arguments: [("c2c1", "13+1"), ("c4c3", "23+1"), ("c6c5", "33+1"),
                      ("c2d2", "13=4"), ("c4b4", "23=2"), ("c6d6", "33=4")])
    func blackThreeOnAFile(move: String, expected: String) {
        #expect(read(move, from: "4k2/2p4/7/2p4/7/2p4/3K3 b - - 0 1") == expected)
    }

    @Test("Black at 2-2: both files indexed from Black's front, the lone soldier plain",
          arguments: [("b3b2", "12+1"), ("b5b4", "22+1"),
                      ("d3d2", "14+1"), ("d5d4", "24+1"),
                      ("f3f2", "P6+1"), ("f3g3", "P6=7"),
                      ("b3a3", "12=1"), ("d3e3", "14=5")])
    func blackTwoDoubledFiles(move: String, expected: String) {
        #expect(read(move, from: "3k3/7/1p1p3/7/1p1p1p1/7/3K3 b - - 0 1") == expected)
    }

    @Test("Black at 3-2, every soldier on both files",
          arguments: [("b1a1", "12=1"), ("b1c1", "12=3"),
                      ("b3b2", "22+1"), ("b5b4", "32+1"),
                      ("d3d2", "14+1"), ("d5d4", "24+1"), ("d5c5", "24=3")])
    func blackThreeTwo(move: String, expected: String) {
        #expect(read(move, from: "3k3/7/1p1p3/7/1p1p3/7/1p1K3 b - - 0 1") == expected)
    }

    @Test("A capture renders exactly as the quiet move would")
    func captureCarriesNoMark() {
        let quiet = "3k3/7/3p3/7/7/7/3K3 b - - 0 1"
        let capture = "3k3/7/3p3/3P3/7/7/3K3 b - - 0 1"
        #expect(read("d5d4", from: quiet) == "P4+1")
        #expect(read("d5d4", from: capture) == "P4+1")
    }

    @Test("A whole line, read as it was written, ending in a mate that carries no marker")
    func theLineFromTheStart() throws {
        let placements = [
            Self.start,
            "rcnkncr/p1ppp1p/7/7/1C5/P1PPP1P/R1NKNCR b - - 1 1",
            "r1nkncr/pcppp1p/7/7/1C5/P1PPP1P/R1NKNCR w - - 2 2",
            "r1nkncr/pcppp1p/7/7/3C3/P1PPP1P/R1NKNCR b - - 3 2",
        ]
        let line = try MoveReading.line(for: ["b1b3", "b7b6", "b3d3"],
                                        on: .miniXiangqi) {
            Placement(fen: placements[$0], game: .miniXiangqi)
        }
        #expect(line.map(\.wxf) == ["C6+2", "C2+1", "C6=4"])
        #expect(line.map(\.traditional) == ["炮六进二", "砲2进1", "炮六平四"])
    }

    @Test("Both notations identify the same piece, shape for shape",
          arguments: [
            ("3k3/7/1P1P3/7/1P1P1P1/7/3K3 w - - 0 1", "f3f4", "兵二进一", "P2+1"),
            ("4k2/7/1P5/7/1P5/7/3K3 w - - 0 1", "b5b6", "前兵进一", "P++1"),
            ("4k2/7/1P5/7/1P5/7/3K3 w - - 0 1", "b3b4", "后兵进一", "P-+1"),
            ("4k2/2P4/7/2P4/7/2P4/3K3 w - - 0 1", "c6c7", "前兵进一", "15+1"),
            ("4k2/2P4/7/2P4/7/2P4/3K3 w - - 0 1", "c4c5", "中兵进一", "25+1"),
            ("4k2/2P4/7/2P4/7/2P4/3K3 w - - 0 1", "c2c3", "后兵进一", "35+1"),
            ("4k2/2P4/2P4/2P4/2P4/7/3K3 w - - 0 1", "c5d5", "二兵平四", "25=4"),
            ("3k3/7/1P1P3/7/1P1P1P1/7/3K3 w - - 0 1", "b3b4", "后兵六进一", "26+1"),
            ("3k3/7/1P1P3/7/1P1P1P1/7/3K3 w - - 0 1", "d5d6", "前兵四进一", "14+1"),
            ("3k3/7/1P1P3/7/1P1P3/7/1P1K3 w - - 0 1", "b3b4", "中兵六进一", "26+1"),
            ("3k3/7/1P1P3/7/1P1P3/7/1P1K3 w - - 0 1", "d3d4", "后兵四进一", "24+1"),
          ])
    func bothNotationsIdentifyTheSamePiece(fen: String, move: String,
                                           chinese: String, wxf: String) {
        let played = Move(text: move, on: GameKind.miniXiangqi.board)!
        let placement = Placement(fen: fen, game: .miniXiangqi)
        #expect(MoveNotation.text(for: played, in: placement) == chinese)
        #expect(WXFNotation.text(for: played, in: placement) == wxf)
    }

    @Test("A reading carries both notations and the style selects between them")
    func aReadingCarriesBoth() {
        let reading = MoveReading(of: Move(text: "b1b3", on: GameKind.miniXiangqi.board)!,
                                  in: Placement(fen: Self.start, game: .miniXiangqi))
        #expect(reading.text(in: .traditional) == "炮六进二")
        #expect(reading.text(in: .wxf) == "C6+2")
    }

    @Test("An unchosen 记谱法 follows the interface language",
          arguments: [("zh-Hans", NotationStyle.traditional),
                      ("zh-Hant", .traditional),
                      ("zh", .traditional),
                      ("zh-Hans-CN", .traditional),
                      ("zh_CN", .traditional),
                      ("en", .wxf),
                      ("en-GB", .wxf),
                      ("en-US", .wxf)])
    func theUnchosenReadingFollowsTheLanguage(identifier: String,
                                              expected: NotationStyle) {
        #expect(NotationStyle.resolved(forInterfaceLanguage: identifier) == expected)
    }

    @Test("A language that is neither reads WXF, absent or unrecognised alike",
          arguments: ["fr", "ja", "ko-KR", "und", "", "nonsense"])
    func anyOtherLanguageReadsWXF(identifier: String) {
        #expect(NotationStyle.resolved(forInterfaceLanguage: identifier) == .wxf)
        #expect(NotationStyle.resolved(forInterfaceLanguage: nil) == .wxf)
    }

    @Test("It is presentation: the canonical notation is untouched")
    func canonicalNotationIsSeparate() {
        let move = Move(text: "b1b3", on: GameKind.miniXiangqi.board)!
        #expect(move.text == "b1b3")
        #expect(read("b1b3", from: Self.start) != move.text)
    }
}
