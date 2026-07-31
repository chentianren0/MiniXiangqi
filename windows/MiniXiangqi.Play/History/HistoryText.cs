// What a History row says, composed once.
//
// docs/interaction-design.md § History library fixes the row exactly: it is two
// lines, the first is when the game ended, and the second is the accepted
// metadata composition applied to a filed game —
// `模式 · [执子] · 结果 · [结束原因] · 步数` — "which is the save-and-continue
// confirmation's own vocabulary rather than a second one invented here". That is
// literally true of this file: every token below comes from the same table
// PlayText composes the active game's line from, and the middot between two of
// them is the same `metadata.join` format string, applied repeatedly rather than
// once per line length.
//
// Two segments are left out where the line would otherwise say one thing twice.
// **执子** is absent in Free Play. **结束原因** is absent where the result word
// already carries it, which is exactly the ended-early record: `outcome = none`
// holds exactly when `end_reason = ended-early`, so the row shows 提前结束 in the
// result slot and says it once. A resignation keeps its reason, because 红方获胜
// alone does not say whether the loser was mated or resigned.
//
// The imported marker is a leading token on the **date** line rather than a
// segment of the metadata line, which is the Apple frontend's placement and is
// the right one: the list is ordered by the time this library added a record
// while the row states the game's own end, so `导入 ·` is what explains a game
// from last year sitting at the top of it.

using System.Globalization;
using System.Text;
using MiniXiangqi.Core;
using MiniXiangqi.Core.Interop;

namespace MiniXiangqi.Play;

public static class HistoryText
{
    /// <summary>
    /// The row's first line: when the game ended, with the imported marker in
    /// front of it where the record came from a file.
    /// </summary>
    public static string WhenLine(this RecordSummary record)
    {
        string when = record.EndedAtText();
        return record.IsImported()
            ? Strings.Join(Strings.Get("metadata.imported"), when)
            : when;
    }

    /// <summary>
    /// The row's second line: `模式 · [执子] · 结果 · [结束原因] · 步数`.
    ///
    /// It never truncates — every token in it is contract-required row content —
    /// so the surface that draws it wraps instead.
    /// </summary>
    public static string MetadataLine(this RecordSummary record)
    {
        List<string> parts =
        [
            Strings.Get(record.Mode == Mxq.MXQ_PLAY_MODE_HUMAN_VS_AI
                ? "mode.humanVersusAI"
                : "mode.freePlay"),
        ];

        // Absent in Free Play, where the turn status omits a controller label for
        // the same reason: one person controls both sides.
        if (record.Mode == Mxq.MXQ_PLAY_MODE_HUMAN_VS_AI && record.HumanSide is
            Mxq.MXQ_COLOR_RED or Mxq.MXQ_COLOR_BLACK)
        {
            parts.Add(Strings.Get(record.HumanSide == Mxq.MXQ_COLOR_BLACK
                ? "metadata.youBlack"
                : "metadata.youRed"));
        }

        parts.Add(record.ResultText());
        if (record.ReasonText() is { Length: > 0 } reason)
        {
            parts.Add(reason);
        }

        parts.Add(record.MoveCountText());

        string line = parts[0];
        for (int index = 1; index < parts.Count; index++)
        {
            line = Strings.Join(line, parts[index]);
        }

        return line;
    }

    /// <summary>
    /// What a screen reader reads for the row: the two lines it shows, in the
    /// order it shows them. Narrator gets the row's content rather than a name
    /// invented for it, which is the basic level docs/interaction-design.md's
    /// accessibility section asks of this platform.
    /// </summary>
    public static string RowLabel(this RecordSummary record) =>
        record.WhenLine() + " " + record.MetadataLine();

    public static bool IsImported(this RecordSummary record) =>
        record.Provenance == Mxq.MXQ_PROVENANCE_IMPORTED;

    /// <summary>
    /// The result slot. An ended-early record has no competitive result, and
    /// `outcome = none` holds exactly when the reason is ended-early, so the
    /// reason stands in the slot and the line says it once.
    /// </summary>
    public static string ResultText(this RecordSummary record) => record.Outcome switch
    {
        Mxq.MXQ_OUTCOME_RED_WINS => Strings.Get("result.redWins"),
        Mxq.MXQ_OUTCOME_BLACK_WINS => Strings.Get("result.blackWins"),
        Mxq.MXQ_OUTCOME_DRAW => Strings.Get("result.draw"),
        _ => Strings.Get("reason.endedEarly"),
    };

    /// <summary>
    /// The reason beside the result, where the result does not already carry it
    /// and where there is one at all.
    /// </summary>
    public static string? ReasonText(this RecordSummary record)
    {
        if (record.Outcome == Mxq.MXQ_OUTCOME_NONE)
        {
            return null;
        }

        return record.EndReason switch
        {
            Mxq.MXQ_END_REASON_CHECKMATE => Strings.Get("reason.checkmate"),
            Mxq.MXQ_END_REASON_STALEMATE => Strings.Get("reason.stalemate"),
            Mxq.MXQ_END_REASON_THREEFOLD_REPETITION => Strings.Get("reason.threefoldRepetition"),
            Mxq.MXQ_END_REASON_PERPETUAL_CHECK => Strings.Get("reason.perpetualCheck"),
            Mxq.MXQ_END_REASON_PERPETUAL_CHASE => Strings.Get("reason.perpetualChase"),
            Mxq.MXQ_END_REASON_MUTUAL_PERPETUAL_CHECK => Strings.Get("reason.mutualPerpetualCheck"),
            Mxq.MXQ_END_REASON_MUTUAL_PERPETUAL_CHASE => Strings.Get("reason.mutualPerpetualChase"),
            Mxq.MXQ_END_REASON_RESIGNATION => Strings.Get("reason.resignation"),
            Mxq.MXQ_END_REASON_ENDED_EARLY => Strings.Get("reason.endedEarly"),
            _ => null,
        };
    }

    /// <summary>
    /// The integer, a space, and the unit — `42 步`. It counts plies, which is
    /// what 步 means, and the *one* variant is a key of its own on a frontend
    /// with no String Catalog.
    /// </summary>
    public static string MoveCountText(this RecordSummary record) => Strings.Format(
        record.MoveCount == 1 ? "metadata.moveCount.one" : "metadata.moveCount",
        record.MoveCount);

    /// <summary>
    /// **The game's own end**, in the reader's locale, calendar and time zone.
    ///
    /// docs/interaction-design.md's accepted form is the system's *today* or
    /// *yesterday* word plus the time for those two days, and a numeric date with
    /// a four-digit year plus the time otherwise. **Windows takes the second
    /// branch on every day**, and that is a Windows clause rather than an
    /// oversight. Neither formatter an app composes dates with has a relative
    /// form: .NET's globalization data has none, and WinRT's `DateTimeFormatter`
    /// has short and long dates and nothing between them. The shell does have one
    /// — `SHFormatDateTime` with `FDTF_RELATIVE`, which an unpackaged app may
    /// P/Invoke — and it is the wrong source twice: it formats from the user
    /// locale rather than from the language the app is running in, so a Chinese
    /// row would read *Today*; and it takes no format control, so the four-digit
    /// year the clause asks for cannot be had from it. What was left was to write
    /// 今天 into the string table, which would be the app supplying a word the
    /// clause assigns to the system and inventing the day boundary it depends on,
    /// or to lose the time; the time is what the clause says the branch exists
    /// for — "it is what tells two games played on one day apart" — and it is
    /// present here on every day.
    ///
    /// **No date or time pattern is written here.** Both halves are the culture's
    /// own — its short date and its short time, which is exactly the pair .NET's
    /// general-short format composes — with one adjustment the clause itself
    /// demands: a culture whose short date abbreviates the year to two digits has
    /// that one field widened to four. Whether the clock reads 14:32 or 2:32 PM
    /// stays the reader's system setting's to say.
    /// </summary>
    public static string EndedAtText(this RecordSummary record) =>
        Moment(record.EndedAtMs, CultureInfo.CurrentCulture);

    public static string Moment(long epochMilliseconds, CultureInfo culture)
    {
        DateTime local = DateTimeOffset.FromUnixTimeMilliseconds(epochMilliseconds).LocalDateTime;
        string date = WithFourDigitYear(culture.DateTimeFormat.ShortDatePattern);
        return local.ToString(date + " " + culture.DateTimeFormat.ShortTimePattern, culture);
    }

    /// <summary>
    /// Widen a two-digit year in a culture's own short-date pattern, and change
    /// nothing else about it. Quoted literals are skipped, because a `y` inside
    /// one is a letter of some language rather than a field.
    /// </summary>
    public static string WithFourDigitYear(string pattern)
    {
        StringBuilder widened = new(pattern.Length + 2);
        char quote = '\0';

        for (int index = 0; index < pattern.Length;)
        {
            char character = pattern[index];
            if (quote != '\0')
            {
                widened.Append(character);
                index++;
                if (character == quote)
                {
                    quote = '\0';
                }

                continue;
            }

            if (character is '\'' or '"')
            {
                quote = character;
                widened.Append(character);
                index++;
                continue;
            }

            if (character != 'y')
            {
                widened.Append(character);
                index++;
                continue;
            }

            int run = 0;
            while (index + run < pattern.Length && pattern[index + run] == 'y')
            {
                run++;
            }

            widened.Append('y', Math.Max(run, 4));
            index += run;
        }

        return widened.ToString();
    }

    /// <summary>
    /// The name an exported file is offered under, built from the game's own end
    /// in a fixed, machine-ordered form.
    ///
    /// This is the deliberate and narrow exception to the localization rule: a
    /// displayed date belongs to the reader and a filename belongs to the file,
    /// so it is the invariant culture and a written pattern here — the one place
    /// in this frontend that is right to write one. It is the game's end rather
    /// than the export event because the export event is regenerated every time,
    /// and the same game would otherwise arrive under a different name on every
    /// share.
    /// </summary>
    public static string SuggestedFileName(this RecordSummary record) =>
        DateTimeOffset.FromUnixTimeMilliseconds(record.EndedAtMs)
            .LocalDateTime
            .ToString("'minixiangqi-'yyyy-MM-dd-HHmm", CultureInfo.InvariantCulture)
        + ".mxq";
}
