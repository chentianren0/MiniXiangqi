import Testing
@testable import MiniXiangqi

@Suite("Traditional notation")
@MainActor
struct MoveNotationTests {
    private func read(_ move: String, from fen: String,
                      game: GameKind = .miniXiangqi) -> String {
        MoveNotation.text(for: Move(text: move, on: game.board)!,
                          in: Placement(fen: fen, game: game))
    }

    private static let start = "rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1"

    @Test("Red numbers files from its own right, in Chinese numerals")
    func redFileNumbering() {
        #expect(read("b1b4", from: Self.start) == "炮六进三")
        #expect(read("f1f4", from: Self.start) == "炮二进三")
    }

    @Test("Black numbers files from its own right, in Arabic digits")
    func blackFileNumbering() {
        #expect(read("a6a5", from: Self.start) == "卒1进1")
        #expect(read("b7b4", from: Self.start) == "砲2进3")
    }

    @Test("进 counts ranks for a chariot, cannon, soldier or general")
    func forwardCountsRanks() {
        #expect(read("a1a4", from: "rcnkncr/p1ppp1p/7/7/7/2PPP2/R1NKNCR w - - 0 1") == "俥七进三")
    }

    @Test("退 counts ranks, and is measured from the mover's own end")
    func backwardCountsRanks() {
        let fen = "rcnkncr/p1ppp1p/7/2R4/7/P1PPP1P/1CNKNCR w - - 0 1"
        #expect(read("c4c3", from: fen) == "俥五退一")
    }

    @Test("平 carries the destination file, not a distance")
    func acrossCarriesTheFile() {
        let fen = "rcnkncr/p1ppp1p/7/2R4/7/P1PPP1P/1CNKNCR w - - 0 1"
        #expect(read("c4f4", from: fen) == "俥五平二")
    }

    @Test("A horse's value is its destination file, because it moves off the line",
          arguments: [("d4c6", "傌四进五"), ("d4e6", "傌四进三"),
                      ("d4c2", "傌四退五"), ("d4e2", "傌四退三")])
    func horseNamesItsDestinationFile(move: String, expected: String) {
        #expect(read(move, from: "rc1k1cr/p1ppp1p/7/3N3/7/P1PPP1P/RC1K1CR w - - 0 1") == expected)
    }

    @Test("Advisors and elephants name their destination file on the 9x10 board")
    func xiangqiDiagonalPiecesNameTheirDestinationFile() {
        let redAdvisor = "5k3/9/9/9/9/9/9/9/3K5/3A5 w - - 0 1"
        let redElephant = "5k3/9/9/9/9/9/9/9/3K5/2B6 w - - 0 1"
        let blackAdvisor = "3a1k3/9/9/9/9/9/9/9/9/3K5 b - - 0 1"
        let blackElephant = "2b2k3/9/9/9/9/9/9/9/9/3K5 b - - 0 1"

        #expect(read("d1e2", from: redAdvisor, game: .xiangqi) == "仕六进五")
        #expect(read("c1e3", from: redElephant, game: .xiangqi) == "相七进五")
        #expect(read("d10e9", from: blackAdvisor, game: .xiangqi) == "士4进5")
        #expect(read("c10e8", from: blackElephant, game: .xiangqi) == "象3进5")
    }

    @Test("Xiangqi numbers all nine files and scans all ten ranks")
    func xiangqiUsesItsWholeBoard() {
        let redEdges = "5k3/9/9/9/9/9/9/9/9/R2K4R w - - 0 1"
        let blackEdges = "r2k4r/9/9/9/9/9/9/9/9/5K3 b - - 0 1"
        let doubled = "R4k3/9/9/9/9/9/9/9/R8/3K5 w - - 0 1"

        #expect(read("a1a2", from: redEdges, game: .xiangqi) == "俥九进一")
        #expect(read("i1i2", from: redEdges, game: .xiangqi) == "俥一进一")
        #expect(read("a10a9", from: blackEdges, game: .xiangqi) == "车1进1")
        #expect(read("i10i9", from: blackEdges, game: .xiangqi) == "车9进1")
        #expect(read("a10b10", from: doubled, game: .xiangqi) == "前俥平八")
    }

    @Test("The general is a line piece here: ranks after 进, a file after 平")
    func generalCountsRanksAndNamesItsFile() {
        let fen = "3k3/7/3p3/7/7/7/3K3 w - - 0 1"
        #expect(read("d1d2", from: fen) == "帅四进一")
        #expect(read("d1c1", from: fen) == "帅四平五")
    }

    @Test("With two on a file the disambiguator OPENS the move and replaces the file")
    func twoOnAFileOpenTheMove() {
        let fen = "3k3/7/1C5/7/7/1C5/3K3 w - - 0 1"
        #expect(read("b5b3", from: fen) == "前炮退二")
        #expect(read("b2b1", from: fen) == "后炮退一")
    }

    @Test("前 is the piece nearer the opponent, for each side in turn")
    func frontIsRelativeToTheMover() {
        let red = "3k3/7/7/7/1C5/1C5/3K3 w - - 0 1"
        #expect(read("b3b5", from: red) == "前炮进二")

        let black = "3k3/1c5/1c5/7/7/7/3K3 b - - 0 1"
        #expect(read("b5b3", from: black) == "前砲进2")
    }

    @Test("Three on a file take 前, 中 and 后")
    func threeOnAFile() {
        let fen = "3k3/7/1P5/7/1P5/7/1P1K3 w - - 0 1"
        #expect(read("b5b6", from: fen) == "前兵进一")
        #expect(read("b3b4", from: fen) == "中兵进一")
        #expect(read("b1b2", from: fen) == "后兵进一")
    }

    @Test("Four or more on a file are numbered from the front")
    func fourOnAFile() {
        let fen = "2k4/1P5/7/1P5/7/1P5/1P1K3 w - - 0 1"
        #expect(read("b6b7", from: fen) == "一兵进一")
        #expect(read("b1a1", from: fen) == "四兵平七")
    }

    @Test("The ordinal is Chinese for Black too, because it continues 前/中/后")
    func blackOrdinalIsChinese() {
        let fen = "2k4/1p5/7/1p5/7/1p5/1p1K3 b - - 0 1"
        #expect(read("b1a1", from: fen) == "一卒平1")
        #expect(read("b6b5", from: fen) == "四卒进1")
    }

    @Test("A second doubled file brings the origin file back after the name")
    func twoDoubledFilesRestoreTheFile() {
        let fen = "3k3/7/1P1P3/7/1P1P1P1/7/3K3 w - - 0 1"
        #expect(read("b5b6", from: fen) == "前兵六进一")
        #expect(read("b3b4", from: fen) == "后兵六进一")
        #expect(read("d5d6", from: fen) == "前兵四进一")
        #expect(read("f3f4", from: fen) == "兵二进一")
    }

    @Test("Three and two across two files keep 前, 中 and 后, with the file")
    func threeTwoShapeKeepsItsWords() {
        let fen = "3k3/7/1P1P3/7/1P1P3/7/1P1K3 w - - 0 1"
        #expect(read("b5b6", from: fen) == "前兵六进一")
        #expect(read("b3b4", from: fen) == "中兵六进一")
        #expect(read("b1b2", from: fen) == "后兵六进一")
        #expect(read("d3d4", from: fen) == "后兵四进一")
    }

    @Test("Black's restored file is Arabic, like every number of Black's")
    func blackRestoredFileIsArabic() {
        let fen = "3k3/7/1p1p3/7/1p1p3/7/3K3 b - - 0 1"
        #expect(read("b3b2", from: fen) == "前卒2进1")
        #expect(read("b5b4", from: fen) == "后卒2进1")
        #expect(read("d3d2", from: fen) == "前卒4进1")
    }

    @Test("A capture renders exactly as the quiet move would")
    func captureCarriesNoMark() {
        let quiet = "3k3/7/3p3/7/7/7/3K3 b - - 0 1"
        let capture = "3k3/7/3p3/3P3/7/7/3K3 b - - 0 1"
        #expect(read("d5d4", from: quiet) == "卒4进1")
        #expect(read("d5d4", from: capture) == "卒4进1")
    }

    @Test("It is presentation: the canonical notation is untouched")
    func canonicalNotationIsSeparate() {
        let move = Move(text: "b1b4", on: GameKind.miniXiangqi.board)!
        #expect(move.text == "b1b4")
        #expect(read("b1b4", from: Self.start) != move.text)
    }
}
