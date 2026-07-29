// The notation a player reads, checked clause by clause against
// docs/interaction-design.md, "User-visible notation".
//
// These exist because the move list had no assertion anywhere: a review
// replaced MoveNotation.text with a constant and the whole suite stayed green.
// Every case below names the rule it holds in place.

import Testing
@testable import MiniXiangqi

@Suite("Traditional notation")
@MainActor
struct MoveNotationTests {

    private func read(_ move: String, from fen: String) -> String {
        MoveNotation.text(for: Move(text: move)!, in: Placement(fen: fen))
    }

    private static let start = "rcnkncr/p1ppp1p/7/7/7/P1PPP1P/RCNKNCR w - - 0 1"

    // MARK: - Files are numbered from each player's own right

    @Test("Red numbers files from its own right, in Chinese numerals")
    func redFileNumbering() {
        // b1 is Red's file 6: its right is file g, so a…g reads 七…一.
        #expect(read("b1b4", from: Self.start) == "炮六进三")
        #expect(read("f1f4", from: Self.start) == "炮二进三")
    }

    @Test("Black numbers files from its own right, in Arabic digits")
    func blackFileNumbering() {
        // Black's right is file a, so a…g reads 1…7. Every number in the move
        // is Arabic, not only the file.
        #expect(read("a6a5", from: Self.start) == "卒1进1")
        #expect(read("b7b4", from: Self.start) == "砲2进3")
    }

    // MARK: - Direction and value

    @Test("进 counts ranks for a chariot, cannon, soldier or general")
    func forwardCountsRanks() {
        // The a-file cleared so the chariot on a1 has somewhere to go.
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
        #expect(read(move, from: "rck1kcr/p1ppp1p/7/3N3/7/P1PPP1P/RC1K1CR w - - 0 1") == expected)
    }

    // MARK: - Two or more of a type on one file

    @Test("With two on a file the disambiguator OPENS the move and replaces the file")
    func twoOnAFileOpenTheMove() {
        // 前炮退二, never 炮前退二, and never a file as well.
        // Cannons on b5 and b2: rank 7 is listed first, so this is
        // 3k3 / 7 / 1C5 / 7 / 7 / 1C5 / 3K3.
        let fen = "3k3/7/1C5/7/7/1C5/3K3 w - - 0 1"
        #expect(read("b5b3", from: fen) == "前炮退二")
        #expect(read("b2b1", from: fen) == "后炮退一")
    }

    @Test("前 is the piece nearer the opponent, for each side in turn")
    func frontIsRelativeToTheMover() {
        // Red's front is the higher rank; Black's is the lower. The sense is
        // relative to the mover, so it does not change when the board is turned.
        // Red's cannons on b3 and b2; Black's on b6 and b5.
        let red = "3k3/7/7/7/1C5/1C5/3K3 w - - 0 1"
        #expect(read("b3b5", from: red) == "前炮进二")

        let black = "3k3/1c5/1c5/7/7/7/3K3 b - - 0 1"
        #expect(read("b5b3", from: black) == "前砲进2")
    }

    @Test("Three on a file take 前, 中 and 后")
    func threeOnAFile() {
        // Reachable here: five soldiers a side, moving sideways from the start.
        // Soldiers on b5, b3 and b1, each with a square in front of it.
        let fen = "3k3/7/1P5/7/1P5/7/1P1K3 w - - 0 1"
        #expect(read("b5b6", from: fen) == "前兵进一")
        #expect(read("b3b4", from: fen) == "中兵进一")
        #expect(read("b1b2", from: fen) == "后兵进一")
    }

    @Test("Four or more on a file are numbered from the front")
    func fourOnAFile() {
        // Soldiers on b6, b4, b2 and b1.
        let fen = "3k3/1P5/7/1P5/7/1P5/1P1K3 w - - 0 1"
        #expect(read("b6b7", from: fen) == "一兵进一")
        #expect(read("b1a1", from: fen) == "四兵平七")
    }

    @Test("The ordinal is Chinese for Black too, because it continues 前/中/后")
    func blackOrdinalIsChinese() {
        // The ordinal is the positional word carried past three, not a number
        // in the move, so it does not follow Black's Arabic numerals: 一卒进1,
        // never 1卒进1. Black soldiers on b6, b4, b2 and b1; Black's front is
        // the lowest rank.
        let fen = "3k3/1p5/7/1p5/7/1p5/1p1K3 b - - 0 1"
        #expect(read("b1a1", from: fen) == "一卒平1")
        #expect(read("b6b5", from: fen) == "四卒进1")
    }

    // MARK: - More than one doubled file

    @Test("A second doubled file brings the origin file back after the name")
    func twoDoubledFilesRestoreTheFile() {
        // Red soldiers paired on b and d, with a lone one on f: 前 alone no
        // longer says which pair moved, so the pairs carry their file — and
        // the lone soldier keeps the plain form untouched.
        let fen = "3k3/7/1P1P3/7/1P1P1P1/7/3K3 w - - 0 1"
        #expect(read("b5b6", from: fen) == "前兵六进一")
        #expect(read("b3b4", from: fen) == "后兵六进一")
        #expect(read("d5d6", from: fen) == "前兵四进一")
        #expect(read("f3f4", from: fen) == "兵二进一")
    }

    @Test("Three and two across two files keep 前, 中 and 后, with the file")
    func threeTwoShapeKeepsItsWords() {
        // All five soldiers: three on b, two on d. The words stay the words;
        // only the file returns.
        let fen = "3k3/7/1P1P3/7/1P1P3/7/1P1K3 w - - 0 1"
        #expect(read("b5b6", from: fen) == "前兵六进一")
        #expect(read("b3b4", from: fen) == "中兵六进一")
        #expect(read("b1b2", from: fen) == "后兵六进一")
        #expect(read("d3d4", from: fen) == "后兵四进一")
    }

    @Test("Black's restored file is Arabic, like every number of Black's")
    func blackRestoredFileIsArabic() {
        // Black soldiers paired on b and d. The restored file follows the
        // ordinary numbering rule — only the ordinal above is outside it.
        let fen = "3k3/7/1p1p3/7/1p1p3/7/3K3 b - - 0 1"
        #expect(read("b3b2", from: fen) == "前卒2进1")
        #expect(read("b5b4", from: fen) == "后卒2进1")
        #expect(read("d3d2", from: fen) == "前卒4进1")
    }

    // MARK: - Captures

    @Test("A capture renders exactly as the quiet move would")
    func captureCarriesNoMark() {
        // The same soldier push with and without a red soldier standing on the
        // destination: one string, no capture mark.
        let quiet = "3k3/7/3p3/7/7/7/3K3 b - - 0 1"
        let capture = "3k3/7/3p3/3P3/7/7/3K3 b - - 0 1"
        #expect(read("d5d4", from: quiet) == "卒4进1")
        #expect(read("d5d4", from: capture) == "卒4进1")
    }

    // MARK: - What it is not

    @Test("It is presentation: the canonical notation is untouched")
    func canonicalNotationIsSeparate() {
        let move = Move(text: "b1b4")!
        #expect(move.text == "b1b4")
        #expect(read("b1b4", from: Self.start) != move.text)
    }
}
