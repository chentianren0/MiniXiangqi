// Every string this frontend shows, in both supported languages.
//
// docs/copy.md is the string of record: it owns the pair and the symbolic key,
// the Simplified Chinese is normative, and the English is a translation of it.
// This table is the Windows frontend's copy of that contract, keyed identically,
// and MiniXiangqi.Smoke checks it against docs/copy.md mechanically — which is
// the agreement check that document's localization process asks CI for, now that
// there is a CI to ask.
//
// Why a table in C# rather than a .resw and a PRI. Three reasons, and the third
// is the one that decided it:
//
//   * the packaging build is what owns resource packaging, and it does not
//     exist yet — windows/README.md records the Windows App SDK version, the
//     .NET version and the packaging flags as unpinned until it does;
//   * an unpackaged app's resource lookup is a deployment question rather than
//     a copy question, and answering it before the packaging build would be
//     answering it twice;
//   * the offscreen render harness has to produce the board in both languages
//     without a XAML resource context, and a table it can read is what lets the
//     evidence show both.
//
// The language is the operating system's, per docs/interaction-design.md's
// localization rule: the app offers no interface-language control of its own,
// and on Windows it follows the system's language preference list — which is
// exactly what .NET resolves CurrentUICulture from.

using System.Collections.Immutable;
using System.Globalization;

namespace MiniXiangqi.Play;

/// <summary>One row of the string table: the normative Chinese and its approved English.</summary>
public readonly record struct LocalizedString(string Chinese, string English);

public static class Strings
{
    /// <summary>
    /// Which language a lookup answers in. Null follows the operating system,
    /// which is the product behaviour; the render harness sets it so that one
    /// process can draw both.
    /// </summary>
    public static bool? PrefersChinese { get; set; }

    public static bool IsChinese =>
        PrefersChinese
        ?? CultureInfo.CurrentUICulture.TwoLetterISOLanguageName.Equals("zh", StringComparison.OrdinalIgnoreCase);

    public static string Get(string key) =>
        Table.TryGetValue(key, out LocalizedString row)
            ? (IsChinese ? row.Chinese : row.English)
            : key;

    /// <summary>
    /// A composed string. Its separator is copy — an ideographic space in
    /// Chinese and an ordinary one in English, a middot with its own spacing in
    /// both — so it is a format string in the table rather than punctuation
    /// hard-coded around a translated fragment.
    /// </summary>
    public static string Format(string key, params object[] arguments) =>
        string.Format(CultureInfo.CurrentCulture, Get(key), arguments);

    /// <summary>Joins two metadata tokens with the accepted middot format.</summary>
    public static string Join(string first, string second) => Format("metadata.join", first, second);

    /// <summary>
    /// The table. Composed strings hold .NET's placeholders rather than
    /// docs/copy.md's `%1$@`; the mechanical check translates between the two
    /// rather than either side pretending the other's spelling.
    /// </summary>
    public static readonly ImmutableDictionary<string, LocalizedString> Table =
        new Dictionary<string, LocalizedString>(StringComparer.Ordinal)
        {
            // Controls.
            ["control.undo"] = new("悔棋", "Undo"),
            ["control.claimDraw"] = new("判和", "Claim Draw"),
            ["control.flipBoard"] = new("翻转棋盘", "Flip Board"),
            ["control.resign"] = new("认输", "Resign"),
            ["control.newGame"] = new("开始新对局", "New Game"),
            ["control.save"] = new("保存", "Save"),
            ["control.saveAndNewGame"] = new("保存并开始新对局", "Save and New Game"),
            ["control.done"] = new("完成", "Done"),
            ["control.close"] = new("关闭", "Close"),
            ["control.cancel"] = new("取消", "Cancel"),
            ["control.tryAgain"] = new("重试", "Try Again"),
            ["control.later"] = new("稍后", "Later"),
            ["control.keepPlaying"] = new("继续对局", "Keep Playing"),
            ["control.endAsDraw"] = new("以和棋结束", "End as a Draw"),

            // Turn status.
            ["status.redToMove"] = new("轮到红方", "Red to Move"),
            ["status.blackToMove"] = new("轮到黑方", "Black to Move"),
            ["status.check"] = new("将军", "Check"),
            // The separator is an ideographic space in Chinese and an ordinary
            // space in English.
            ["status.sideToMove.checked"] = new("{0}　{1}", "{0} {1}"),
            ["status.drawAvailable"] = new("可判和", "Draw Available"),
            ["status.controller.you"] = new("你", "You"),
            ["status.controller.ai"] = new("AI", "AI"),
            ["status.aiThinking"] = new("AI 正在思考", "AI is thinking"),
            ["status.aiUnavailable"] = new("AI 暂时无法启动", "The AI can't start right now"),
            ["status.redWins"] = new("红方胜", "Red Wins"),
            ["status.blackWins"] = new("黑方胜", "Black Wins"),
            ["status.draw"] = new("和局", "Draw"),
            ["status.saveFailed"] = new("无法保存这一步，请重试。", "Couldn't save that move. Please try again."),

            // Result notice.
            ["result.redWins"] = new("红方获胜", "Red Wins"),
            ["result.blackWins"] = new("黑方获胜", "Black Wins"),
            ["result.draw"] = new("和棋", "Draw"),
            ["result.recorded"] = new("已记录到历史", "Saved to History"),
            // The separator is an ideographic comma in Chinese and a
            // comma-space in English.
            ["result.announcement"] = new("{0}，{1}", "{0}, {1}"),

            // Result reasons. One vocabulary, used by the result notice's
            // second line and by the turn status.
            ["reason.checkmate"] = new("将死", "Checkmate"),
            ["reason.stalemate"] = new("困毙", "Stalemate"),
            ["reason.threefoldRepetition"] = new("三次重复", "Threefold Repetition"),
            ["reason.perpetualCheck"] = new("长将", "Perpetual Check"),
            ["reason.perpetualChase"] = new("长捉", "Perpetual Chase"),
            ["reason.mutualPerpetualCheck"] = new("双方长将", "Mutual Perpetual Check"),
            ["reason.mutualPerpetualChase"] = new("双方长捉", "Mutual Perpetual Chase"),
            ["reason.resignation"] = new("认输", "Resignation"),
            ["reason.endedEarly"] = new("提前结束", "Ended Early"),

            // Alerts.
            ["alert.resign.title"] = new("认输？", "Resign?"),
            ["alert.resign.message"] = new("认输后本局将记为你落败。", "Resigning records this game as your loss."),
            ["alert.claimDraw.title"] = new("局面已三次重复", "This position has occurred three times."),
            ["alert.claimDraw.message"] = new("可以和棋结束。", "You can end the game as a draw."),
            ["alert.saveFailed.title"] = new("无法保存对局", "Couldn't Save the Game"),
            ["alert.saveFailed.message"] = new("当前对局仍然保留。请重试。", "The current game is unchanged. Please try again."),
            ["alert.aiUnavailable.title"] = new("无法启动 AI 对手", "Couldn't Start the AI Opponent"),
            ["alert.aiUnavailable.message"] = new(
                "当前可用内存不足。请尝试关闭一些其他 App，然后重试。",
                "There is not enough memory available. Please close some other apps, then try again."),
            ["alert.aiUnavailable.resumeMessage"] = new(
                "当前可用内存不足。对局已保存，可以稍后继续。请尝试关闭一些其他 App，然后重试。",
                "There is not enough memory available. The game is saved and you can continue later. "
                + "Please close some other apps, then try again."),

            // Failure screens. The technical description beneath each title is
            // the core's own diagnostic, which is never localized.
            ["failure.coreDidNotStart"] = new("核心未能启动", "The core did not start"),
            ["failure.gameDidNotStart"] = new("对局未能开始", "The game did not start"),

            // Composition.
            ["metadata.join"] = new("{0} · {1}", "{0} · {1}"),
            ["moveList.rowNumber"] = new("{0}.", "{0}."),
            ["app.displayName"] = new("Mini Xiangqi", "Mini Xiangqi"),

            // Board accessibility. The point description is composed from the
            // square name, then this vocabulary in the order the board contract
            // gives.
            ["board.a11y.red"] = new("红", "Red"),
            ["board.a11y.black"] = new("黑", "Black"),
            ["board.a11y.empty"] = new("空", "Empty"),
            ["board.a11y.selected"] = new("已选择", "Selected"),
            ["board.a11y.legalMove"] = new("可走", "Legal Move"),
            ["board.a11y.capture"] = new("可吃", "Capture"),
            ["board.a11y.inCheck"] = new("被将军", "In Check"),

            // Piece names. The accessibility representation switches with the
            // language: Chinese names a piece by the character it carries,
            // because that is what the board shows and what the reader is
            // learning; English names it by its piece name and never by the
            // character. So `b1 红 炮 已选择` is `b1 Red Cannon Selected`. The
            // character is the argument rather than the string, because the ten
            // piece characters are game content and never enter a string table.
            ["piece.general"] = new("{0}", "General"),
            ["piece.chariot"] = new("{0}", "Chariot"),
            ["piece.horse"] = new("{0}", "Horse"),
            ["piece.cannon"] = new("{0}", "Cannon"),
            ["piece.soldier"] = new("{0}", "Soldier"),
        }.ToImmutableDictionary(StringComparer.Ordinal);

    /// <summary>
    /// How a piece is named where words are used rather than the board's own
    /// glyph, which here is only the accessibility label.
    /// </summary>
    public static string Name(PieceKind kind, Side side)
    {
        string key = kind switch
        {
            PieceKind.General => "piece.general",
            PieceKind.Chariot => "piece.chariot",
            PieceKind.Horse => "piece.horse",
            PieceKind.Cannon => "piece.cannon",
            _ => "piece.soldier",
        };
        return Format(key, kind.Character(side));
    }
}
