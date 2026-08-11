// What the screen says, composed once.
//
// The turn status is one coherent description of the current play state, and
// the result notice and the board's accessibility labels draw on the same
// vocabulary, so the composition lives in one place rather than in whichever
// view happened to need it first. Every string comes from the table in
// Strings.cs, which is this frontend's string of record; every separator between
// two of them is a format string from the same table, because what stands
// between two words is copy — an ideographic space in Chinese and an ordinary
// one in English — and a separator hard-coded here would be one language's
// punctuation wrapped around the other language's words.

using MiniXiangqi.Core;
using MiniXiangqi.Core.Interop;

namespace MiniXiangqi.Play;

public static class PlayText
{
    /// <summary>
    /// The turn status's primary line: it always identifies the side to move,
    /// and a finished game says its result instead, because a finished game is
    /// nobody's to move.
    /// </summary>
    public static string PrimaryStatus(this PlaySession play) => play.ResultState switch
    {
        Mxq.MXQ_GAME_RED_WINS => Strings.Get("status.redWins"),
        Mxq.MXQ_GAME_BLACK_WINS => Strings.Get("status.blackWins"),
        Mxq.MXQ_GAME_DRAW => Strings.Get("status.draw"),
        _ => play.SideToMoveLine(),
    };

    /// <summary>
    /// The secondary line: who owns the turn, and what else is true of the
    /// game. The controller label belongs to a turn and stops when the turn
    /// does, and Free Play omits it because the same person controls both
    /// sides.
    /// </summary>
    public static string? SecondaryStatus(this PlaySession play)
    {
        string? claimOrReason = play.ResultState switch
        {
            Mxq.MXQ_GAME_ONGOING => null,
            Mxq.MXQ_GAME_CLAIMABLE_DRAW => Compose(
                Strings.Get("status.drawAvailable"), play.Reason()),
            _ => play.Reason(),
        };

        string? owner = play.IsOver || !play.IsHumanVersusAi
            ? null
            : Strings.Get(play.SideToMove == play.HumanSide
                ? "status.controller.you"
                : "status.controller.ai");

        return Compose(owner, claimOrReason);
    }

    /// <summary>How a result reads. One home for the vocabulary.</summary>
    public static string? Reason(this PlaySession play) => play.ResultReason switch
    {
        Mxq.MXQ_END_REASON_CHECKMATE => Strings.Get("reason.checkmate"),
        Mxq.MXQ_END_REASON_STALEMATE => Strings.Get("reason.stalemate"),
        Mxq.MXQ_END_REASON_THREEFOLD_REPETITION => Strings.Get("reason.threefoldRepetition"),
        Mxq.MXQ_END_REASON_PERPETUAL_CHECK => Strings.Get("reason.perpetualCheck"),
        Mxq.MXQ_END_REASON_PERPETUAL_CHASE => Strings.Get("reason.perpetualChase"),
        Mxq.MXQ_END_REASON_MUTUAL_PERPETUAL_CHECK => Strings.Get("reason.mutualPerpetualCheck"),
        Mxq.MXQ_END_REASON_MUTUAL_PERPETUAL_CHASE => Strings.Get("reason.mutualPerpetualChase"),
        Mxq.MXQ_END_REASON_FIFTY_MOVE_RULE => Strings.Get("reason.fiftyMoveRule"),
        Mxq.MXQ_END_REASON_RESIGNATION => Strings.Get("reason.resignation"),
        Mxq.MXQ_END_REASON_ENDED_EARLY => Strings.Get("reason.endedEarly"),

        // No reason is no words, in every language.
        _ => null,
    };

    /// <summary>The result notice's title, in whichever state it is standing.</summary>
    public static string? NoticeTitle(this PlaySession play) => play.Notice switch
    {
        ResultNotice.Recorded => Strings.Get("result.recorded"),
        ResultNotice.Result => play.ResultState switch
        {
            Mxq.MXQ_GAME_RED_WINS => Strings.Get("result.redWins"),
            Mxq.MXQ_GAME_BLACK_WINS => Strings.Get("result.blackWins"),
            Mxq.MXQ_GAME_DRAW => Strings.Get("result.draw"),
            _ => null,
        },
        _ => null,
    };

    /// <summary>
    /// The active game's metadata line: mode, the human's side where there is
    /// one, what is true of the game now, and the move count.
    ///
    /// docs/interaction-design.md, "Saving the active game before choosing a new
    /// mode": it identifies at least the mode, the human's side when applicable,
    /// and the move count; it shows the side to move for an ongoing game, the
    /// result and reason for a terminal one, and claim availability where it
    /// applies. The accepted example lines are 人机对弈 · 你执红,
    /// 进行中 · 轮到黑方 · 42 步, 红方获胜 · 将死 · 42 步 and
    /// 进行中 · 可判和 · 42 步.
    ///
    /// One line, two surfaces: the Play home's 当前对局 card, and the
    /// save-and-continue confirmation, which puts the same header over the same
    /// line. **Every fact on it is read, not worked out** — the mode and the
    /// human side from the configuration frozen at creation, the state, the
    /// reason and the ply count from the core's own status.
    /// </summary>
    public static string MetadataLine(this PlaySession play)
    {
        List<string> parts =
        [
            Strings.GameName(play.Game),
            Strings.Get(play.IsHumanVersusAi ? "mode.humanVersusAI" : "mode.freePlay"),
        ];

        if (play.HumanSide is { } side)
        {
            parts.Add(Strings.Get(side == Side.Red ? "metadata.youRed" : "metadata.youBlack"));
        }

        parts.AddRange(play.StateParts());
        parts.Add(play.MoveCountText());

        // Applied repeatedly rather than once per line length, because the
        // middot and its spacing are a piece of writing rather than punctuation
        // this file may hard-code around a translated fragment.
        string line = parts[0];
        for (int index = 1; index < parts.Count; index++)
        {
            line = Strings.Join(line, parts[index]);
        }

        return line;
    }

    /// <summary>
    /// What is true of the game right now, in the three exclusive classes the
    /// accepted examples give.
    ///
    /// An ongoing game is 进行中 and whose turn it is. A claimable repetition is
    /// still ongoing — that is the whole point of it being a claim — and what it
    /// adds is the standing offer, in the same words the turn status uses for
    /// it; the side to move gives way to it, as the accepted example line does.
    /// A terminal game is its result and the reason for it, in the longer
    /// register the metadata composition uses everywhere: 红方获胜, not the
    /// status line's 红方胜.
    /// </summary>
    private static string[] StateParts(this PlaySession play)
    {
        string? reason = play.Reason();
        return play.ResultState switch
        {
            Mxq.MXQ_GAME_ONGOING =>
            [
                Strings.Get("metadata.inProgress"),
                Strings.Get(play.SideToMove == Side.Red ? "status.redToMove" : "status.blackToMove"),
            ],
            Mxq.MXQ_GAME_CLAIMABLE_DRAW =>
            [
                Strings.Get("metadata.inProgress"),
                Strings.Get("status.drawAvailable"),
            ],
            Mxq.MXQ_GAME_RED_WINS => Result("result.redWins", reason),
            Mxq.MXQ_GAME_BLACK_WINS => Result("result.blackWins", reason),
            Mxq.MXQ_GAME_DRAW => Result("result.draw", reason),
            _ => [],
        };

        // No reason is no words, so it contributes no segment rather than an
        // empty one.
        static string[] Result(string key, string? reason) =>
            reason is { Length: > 0 } said ? [Strings.Get(key), said] : [Strings.Get(key)];
    }

    /// <summary>
    /// Plies, which is what 步 counts, and the core's own count of them.
    ///
    /// The Apple frontend's catalog holds <c>metadata.moveCount</c> as a String
    /// Catalog plural pattern, which is that platform's own mechanism and not one
    /// this frontend has. So the pattern's *one* variant carries its own key
    /// here, <c>metadata.moveCount.one</c>, and this is the selection a catalog
    /// would have made. A one-ply game is reachable in Free Play, which is why
    /// it is not a case that can be skipped.
    /// </summary>
    private static string MoveCountText(this PlaySession play) => Strings.Format(
        play.Position.PlyCount == 1 ? "metadata.moveCount.one" : "metadata.moveCount",
        play.Position.PlyCount);

    /// <summary>
    /// What a screen reader says about a point: its name, what stands there,
    /// and any state that is on it.
    ///
    /// The point's name is a coordinate and is the same in every language. The
    /// piece is named where the two languages part company — Chinese says the
    /// character on the disc, English says the piece's name — so
    /// <c>b1 红 炮 已选择</c> is <c>b1 Red Cannon Selected</c>.
    /// </summary>
    public static string Describe(this BoardScene scene, Square square)
    {
        List<string> parts = [square.Name];
        if (scene.Placement[square] is { } piece)
        {
            parts.Add(Strings.Get(piece.Side == Side.Red ? "board.a11y.red" : "board.a11y.black"));
            parts.Add(Strings.Name(piece.Kind, piece.Side));
        }
        else
        {
            parts.Add(Strings.Get("board.a11y.empty"));
        }

        if (scene.Selected == square)
        {
            parts.Add(Strings.Get("board.a11y.selected"));
        }

        if (scene.Captures.Contains(square))
        {
            parts.Add(Strings.Get("board.a11y.capture"));
        }
        else if (scene.Destinations.Contains(square))
        {
            parts.Add(Strings.Get("board.a11y.legalMove"));
        }

        if (scene.CheckedGeneral == square)
        {
            parts.Add(Strings.Get("board.a11y.inCheck"));
        }

        return string.Join(' ', parts);
    }

    /// <summary>
    /// Whose turn it is, and the check token where there is one. The token
    /// accompanies the line rather than replacing it: whose turn it is remains
    /// true while they are in check.
    /// </summary>
    private static string SideToMoveLine(this PlaySession play)
    {
        string side = Strings.Get(play.SideToMove == Side.Red ? "status.redToMove" : "status.blackToMove");

        // While a checked general is held the board's rings hide, so the token
        // is what carries check through that gap; it is shown whenever the side
        // to move is in check either way.
        return play.Position.InCheck
            ? Strings.Format("status.sideToMove.checked", side, Strings.Get("status.check"))
            : side;
    }

    /// <summary>
    /// Joins two tokens with the accepted metadata format, applied repeatedly
    /// rather than once per line length, and joins nothing to nothing.
    /// </summary>
    private static string? Compose(string? first, string? second) => (first, second) switch
    {
        (null or "", null or "") => null,
        (null or "", { } only) => only,
        ({ } only, null or "") => only,
        var (one, two) => Strings.Join(one!, two!),
    };
}
