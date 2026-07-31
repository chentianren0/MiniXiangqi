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
            // Navigation and modes. 对局 names the destination, the Play home's
            // own title, and the back control that returns to it — one string
            // for one page, as docs/copy.md keys it.
            ["nav.play"] = new("对局", "Play"),
            ["nav.history"] = new("历史", "History"),
            // The third destination's own name, on the shell's settings item and
            // as the page's title. NavigationView supplies its own word there in
            // whatever language it resolved; the app says its own, because this
            // row is the string of record for it and a platform's word for a
            // destination this contract names would be a second source of truth.
            ["nav.settings"] = new("设置", "Settings"),
            ["nav.resumeGame"] = new("回到对局", "Resume Game"),
            ["mode.humanVersusAI"] = new("人机对弈", "Human versus AI"),
            ["mode.freePlay"] = new("自由对弈", "Free Play"),

            // Controls.
            ["control.undo"] = new("悔棋", "Undo"),
            ["control.startGame"] = new("开始对局", "Start Game"),
            ["control.saveAndContinue"] = new("保存并继续", "Save and Continue"),
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
            ["control.replay"] = new("回放", "Replay"),

            // The History destination's row actions and its two alert
            // acknowledgements. On Windows the context menu is the primary path
            // to the first four, per the platform-adaptation rule: where a
            // platform lacks an idiom used elsewhere — list swipe actions here —
            // the same operations are exposed through that platform's own
            // conventional equivalents.
            ["control.share"] = new("共享", "Share"),
            ["control.delete"] = new("删除", "Delete"),
            ["control.pin"] = new("置顶", "Pin"),
            ["control.unpin"] = new("取消置顶", "Unpin"),
            ["control.import"] = new("导入…", "Import…"),
            ["control.view"] = new("查看", "View"),
            ["control.ok"] = new("好", "OK"),

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
            ["alert.newGame.title"] = new("开始新对局？", "Start a new game?"),
            // One string over one line, wherever that line is shown: the
            // confirmation's metadata header, and the current-game section on
            // the Play home.
            ["alert.newGame.metadataHeader"] = new("当前对局", "Current Game"),
            ["alert.newGame.message"] = new(
                "这盘对局将按当前状态保存到历史。",
                "This game will be saved to History as it is now."),
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
            // The creation failure that is not about memory: the game could not
            // be persisted. It cannot borrow alert.saveFailed's wording, whose
            // message promises that the current game is unchanged — there is no
            // current game to keep.
            ["alert.gameNotStarted.title"] = new("无法开始对局", "Couldn't Start the Game"),
            ["alert.gameNotStarted.message"] = new(
                "保存这盘新对局时出错。请重试。",
                "Saving the new game failed. Please try again."),

            // Deleting a History record. 删除后无法恢复 says *recovered* rather
            // than *undone* on purpose: the app has a visible Undo control that
            // means something else, and there is no deletion Undo.
            ["alert.deleteGame.title"] = new("删除这盘棋？", "Delete this game?"),
            ["alert.deleteGame.message"] = new("删除后无法恢复。", "This game can't be recovered."),
            ["alert.deleteFailed.title"] = new("无法删除这盘棋", "Couldn't Delete This Game"),
            ["alert.deleteFailed.message"] = new(
                "这盘棋仍然保留在历史里。请重试。",
                "This game is still in History. Please try again."),

            // The import answers. Every one of them is a thing that did not
            // happen, and every message says 历史没有改变 explicitly, because no
            // persistent change is the guarantee the core makes and a reader has
            // no other way to know it held. A successful import is not here: the
            // row appearing is its answer.
            ["alert.importDuplicate.title"] = new("这盘棋已经在历史里", "This Game Is Already in History"),
            ["alert.importDuplicate.message"] = new(
                "文件里的对局和历史中的一盘完全相同，所以没有重复添加。",
                "The game in this file is identical to one already in History, so it wasn't added again."),
            ["alert.importConflict.title"] = new(
                "这个文件和历史中的一盘棋冲突",
                "This File Conflicts with a Game in History"),
            ["alert.importConflict.message"] = new(
                "它和历史中的一盘棋是同一局，但内容不同。历史没有改变。如果要用这个文件，请先删除历史中的那一盘。",
                "It is the same game as one in History, but its contents differ. History is unchanged. "
                + "To use this file, delete that game from History first."),
            ["alert.importNewerVersion.title"] = new(
                "这个文件由更新版本的 Mini Xiangqi 创建",
                "This File Was Created by a Newer Version of Mini Xiangqi"),
            ["alert.importNewerVersion.message"] = new(
                "当前版本无法读取它。请更新 Mini Xiangqi 后再试。历史没有改变。",
                "This version can't read it. Update Mini Xiangqi and try again. History is unchanged."),
            ["alert.importUnreadable.title"] = new("无法读取这个对局文件", "Can't Read This Game File"),
            ["alert.importUnreadable.message"] = new(
                "文件的内容无效或过大，无法导入。历史没有改变。请确认文件完整，或者向对方要一份新的。",
                "The file's contents are invalid or too large to import. History is unchanged. "
                + "Check that the file is complete, or ask for a new copy."),
            ["alert.importSaveFailed.title"] = new("无法保存导入的对局", "Couldn't Save the Imported Game"),
            ["alert.importSaveFailed.message"] = new(
                "对局文件没有问题，但保存到历史时出错。历史没有改变。请重试。",
                "The game file is fine, but saving it to History failed. History is unchanged. "
                + "Please try again."),
            ["alert.importDamagedRecord.title"] = new("历史中有一盘损坏的棋", "A Game in History Is Damaged"),
            ["alert.importDamagedRecord.message"] = new(
                "这个文件对应的历史记录已损坏，无法比较或导入。如果要用这个文件，请先删除历史中的那一盘。",
                "The record in History matching this file is damaged, so it can't be compared or "
                + "imported. To use this file, delete that game from History first."),

            // Pre-start setup. 本局设置 names the group and the three options
            // name themselves, so 先后手 is drawn nowhere and is the segmented
            // control's screen-reader name.
            ["setup.thisGame"] = new("本局设置", "This Game"),
            ["setup.firstMover"] = new("先后手", "First Mover"),
            ["setup.iMoveFirst"] = new("我先手", "I Move First"),
            ["setup.aiMovesFirst"] = new("AI 先手", "AI Moves First"),
            ["setup.random"] = new("随机", "Random"),
            ["setup.aiLevel"] = new("AI 等级", "AI Level"),
            ["setup.level.fast"] = new("快速", "Fast"),
            ["setup.level.standard"] = new("标准", "Standard"),
            ["setup.level.deep"] = new("深思", "Deep"),
            ["setup.freePlayExplanation"] = new(
                "你将控制红黑双方，红方先行。",
                "You control both Red and Black. Red moves first."),

            // The Settings destination. Three of the Mac's four groups ship here
            // and every absence is issue #80's owner-decided Windows trim, so
            // 棋盘 and its two rows carry no key below and neither does 触感:
            // the notation has nothing to choose between while the record is the
            // core's own coordinate text, only the 汉字 symbol set is drawn, and
            // the platform has no haptic hardware to drive. The two footers are
            // both here, which is the whole of the accepted two-footer rule —
            // "there are two footers on the screen, and only two" — surviving the
            // trim rather than being restated by it.
            //
            // The six option words below carry no rows of their own: 默认先后手
            // and 默认 AI 等级 offer exactly the choices the pre-start page
            // offers, and docs/copy.md keys them once, under `setup.`, for both.
            ["settings.defaults.group"] = new("人机对弈默认设置", "Human versus AI Defaults"),
            ["settings.defaults.firstMover"] = new("默认先后手", "Default First Mover"),
            ["settings.defaults.aiLevel"] = new("默认 AI 等级", "Default AI Level"),
            ["settings.defaults.footer"] = new(
                "这些设置用于开始新的人机对弈，不会改变进行中的对局。",
                "These settings apply when you start a new Human versus AI game. "
                + "They don't change a game in progress."),
            ["settings.sound.label"] = new("声音", "Sound"),
            ["settings.confirmDelete.label"] = new("删除前确认", "Confirm Before Deleting"),
            ["settings.confirmDelete.footer"] = new(
                "关闭后，删除立即执行。删除无法撤销。",
                "When off, deletion happens immediately. A deletion cannot be undone."),

            // Game metadata: the tokens the active game's line is composed of.
            ["metadata.youRed"] = new("你执红", "You: Red"),
            ["metadata.youBlack"] = new("你执黑", "You: Black"),
            ["metadata.inProgress"] = new("进行中", "In Progress"),
            // 步 is invariant and *move* is not. On Apple this is one String
            // Catalog plural pattern and the platform selects the variant; this
            // frontend has no catalog, so the *one* variant carries its own key
            // and PlayText selects between them.
            ["metadata.moveCount"] = new("{0} 步", "{0} moves"),
            ["metadata.moveCount.one"] = new("{0} 步", "{0} move"),
            // A leading token on a filed record's date line: the list is ordered
            // by when this library added a record while the row states the game's
            // own end, and 导入 is what explains an old game sitting at the top.
            ["metadata.imported"] = new("导入", "Imported"),

            // The History destination: its two sections, and what it says with
            // nothing in it. With nothing pinned there is one unheaded section
            // and the list reads as a plain list of games.
            ["history.section.pinned"] = new("已置顶", "Pinned"),
            ["history.section.others"] = new("其他对局", "Other Games"),
            ["history.empty.title"] = new("还没有历史对局", "No Games Yet"),
            ["history.empty.description"] = new(
                "对局结束后会保存到这里。",
                "Games you finish are saved here."),

            // The step-through viewer. Its four transport controls are icon-only,
            // so each of these is what a screen reader reads and what a pointer's
            // tooltip shows, and none of them is drawn. 自动播放 and 暂停 have no
            // rows here: issue #80's trim makes replay on Windows a step-through
            // viewer, and a string for a control that does not exist would be a
            // string nothing reads.
            ["replay.progress"] = new("{0} / {1}", "{0} / {1}"),
            ["replay.first"] = new("回到开始", "Go to Start"),
            ["replay.previous"] = new("上一步", "Previous Move"),
            ["replay.next"] = new("下一步", "Next Move"),
            ["replay.last"] = new("跳到最后", "Go to End"),

            // Failure screens. The technical description beneath each title is
            // the core's own diagnostic, which is never localized.
            ["failure.coreDidNotStart"] = new("核心未能启动", "The core did not start"),
            ["failure.gameDidNotStart"] = new("对局未能开始", "The game did not start"),
            ["failure.historyDidNotLoad"] = new("历史未能载入", "History did not load"),

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
