// The line leaves out what it would otherwise say twice:
//   - the end reason where the result slot already carries it: a record's
//     result is `none` exactly when its reason is `ended-early`;
//   - the human side in Free Play, where one person plays both sides.
// A resignation keeps its reason: 红方获胜 alone does not tell a player whether
// they were mated or resigned.

import Foundation

@MainActor
extension GameRecord {
    var metadataLine: String {
        var parts = [kind.localizedName, modeText]
        if mode == .humanVersusAI, let humanSide {
            parts.append(kind.youAreText(humanSide))
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
        case .online: String(localized: "mode.online")
        }
    }

    /// 红方获胜 rather than the status line's shorter 红方胜. A record with no
    /// competitive result says why instead.
    var resultText: String {
        switch result ?? .none {
        case .redWins: kind.resultText(.red)
        case .blackWins: kind.resultText(.black)
        case .draw: String(localized: "result.draw")
        case .none: (reason ?? .none).text
        }
    }

    /// The end reason, where it is not already what the result slot said.
    var reasonText: String? {
        guard let reason, (result ?? .none) != .none, reason != .none else { return nil }
        return reason.text
    }

    var moveCountText: String {
        String(format: String(localized: "metadata.moveCount"), moves.count)
    }

    /// The imported marker is on this line, not the metadata one, because it
    /// qualifies the date: an imported game ended wherever it was played.
    var whenText: String {
        guard imported else { return endedAtText }
        return [String(localized: "metadata.imported"), endedAtText]
            .joined(by: String(localized: "metadata.join"))
    }

    /// In the reader's locale, calendar and time zone. No date or time pattern
    /// is written here: 14:32 versus 2:32 PM belongs to the locale and the
    /// reader's system setting.
    var endedAtText: String {
        let endedAt = self.endedAt ?? startedAt
        let calendar = Calendar.current
        if calendar.isDateInToday(endedAt) || calendar.isDateInYesterday(endedAt) {
            // Relative day names (今天, Today) come only from `DateFormatter`.
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
    /// A format string rather than a literal separator, because what surrounds
    /// the separator is each language's to say.
    func joined(by format: String) -> String {
        guard var line = first else { return "" }
        for part in dropFirst() {
            line = String(format: format, line, part)
        }
        return line
    }
}
