// What one stored game says about itself.
//
// docs/interaction-design.md, "History library": each entry shows its date,
// game, mode, result or end reason, and move count, and human-versus-AI entries
// also show the human side. The composition below invents no vocabulary at all
// — it is the metadata line the save-and-continue confirmation already
// accepted, 象棋 · 人机对弈 · 你执红 · 红方获胜 · 将死 · 42 步, applied to a
// filed game rather than to the active one, joined by the same middot.
//
// Two rules about what is *left out*, both because the line would otherwise say
// one thing twice:
//
//   - The end reason is dropped where the result word already carries it, which
//     is exactly the ended-early record: game-data.md makes `outcome = none`
//     true exactly when `end_reason = ended-early`, so the two are one fact.
//     The row shows 提前结束 in the result slot — "result *or* end reason" is
//     what the product contract asks of the row — rather than adding a second
//     word for the absence of a winner.
//   - The human side is dropped in Free Play, where the same person controls
//     both sides and the turn status omits a controller label for the same
//     reason.
//
// A resignation keeps its reason: 红方获胜 alone does not tell a player whether
// they were mated or resigned, and that is the difference the reason is for.

import Foundation

extension RecordSummary {
    /// The metadata line: game, mode, human side, result, reason, move count.
    var metadataLine: String {
        var parts = [game.localizedName, modeText]
        if mode == .humanVersusAI, let humanSide {
            parts.append(humanSide == .red
                         ? String(localized: "metadata.youRed")
                         : String(localized: "metadata.youBlack"))
        }
        parts.append(resultText)
        if let reasonText { parts.append(reasonText) }
        parts.append(moveCountText)
        return parts.joined(by: String(localized: "metadata.join"))
    }

    var modeText: String {
        switch mode {
        case .humanVersusAI: String(localized: "mode.humanVersusAI")
        case .freePlay: String(localized: "mode.freePlay")
        case .nearby: String(localized: "mode.nearby")
        }
    }

    /// The committed outcome, in the register the accepted metadata example
    /// uses — 红方获胜 rather than the status line's shorter 红方胜. A record
    /// with no competitive result says why instead.
    var resultText: String {
        switch outcome {
        case .redWins: String(localized: "result.redWins")
        case .blackWins: String(localized: "result.blackWins")
        case .draw: String(localized: "result.draw")
        case .none: reason.text
        }
    }

    /// The end reason, where it is not already what the result slot said.
    var reasonText: String? {
        guard outcome != .none, reason != .none else { return nil }
        return reason.text
    }

    var moveCountText: String {
        String(format: String(localized: "metadata.moveCount"), moveCount)
    }

    /// When the game ended, and — for a game that came from a file — that it
    /// did.
    ///
    /// The imported marker the contract asks for is a word rather than a glyph,
    /// and it is on this line rather than the metadata one because of what it
    /// explains. The list is ordered by when a record entered *this* library,
    /// and the row shows when the game itself ended; for a game played here
    /// those are one transaction apart, and for an imported one they can be
    /// years apart. 导入 · is what tells a reader why a game from 2024 is
    /// sitting at the top of the list.
    var whenText: String {
        guard imported else { return endedAtText }
        return [String(localized: "metadata.imported"), endedAtText]
            .joined(by: String(localized: "metadata.join"))
    }

    /// The date itself, in the reader's own locale, calendar and time zone.
    ///
    /// Today and yesterday take the system's own day word plus the time; every
    /// other day takes a numeric date and the time. The time is always there,
    /// because it is what tells two games played on one day apart, and the year
    /// is always four digits, because a library kept across years is where a
    /// two-digit one helps least.
    ///
    /// **No date or time pattern is written here, in either branch.** Whether
    /// the clock reads 14:32 or 2:32 PM belongs to the locale and to the
    /// reader's own system setting; a hand-written `HH:mm` would override both.
    var endedAtText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(endedAt) || calendar.isDateInYesterday(endedAt) {
            // Relative day names come only from `DateFormatter`, which is why
            // this is two calls rather than one: 今天 and Today are the
            // system's words, not ours, and writing our own would diverge from
            // the rest of the operating system.
            return Self.relativeFormatter.string(from: endedAt)
        }
        return endedAt.formatted(date: .numeric, time: .shortened)
    }

    private static let relativeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

extension Array where Element == String {
    /// The accepted metadata join, applied repeatedly rather than once per line
    /// length. What a language puts around the separator is that language's to
    /// say, so it is a format string and not a literal.
    func joined(by format: String) -> String {
        guard var line = first else { return "" }
        for part in dropFirst() {
            line = String(format: format, line, part)
        }
        return line
    }
}
