// What the screen says, composed once.
//
// The turn status is one coherent description of the current play state, and
// the result notice and the board's accessibility labels draw on the same
// vocabulary, so the composition lives in one place rather than in whichever
// view happened to need it first. Every string comes from the table in
// Strings.cs, which is docs/copy.md's; every separator between two of them is a
// format string from the same table, because what stands between two words is
// copy — an ideographic space in Chinese and an ordinary one in English — and a
// separator hard-coded here would be one language's punctuation wrapped around
// the other language's words.

using MiniXiangqi.Core.Interop;

namespace MiniXiangqi.Play;

public static class PlayText
{
    /// <summary>
    /// The turn status's primary line: it always identifies the side to move,
    /// and a finished game says its result instead, because a finished game is
    /// nobody's to move.
    /// </summary>
    public static string PrimaryStatus(this PlaySession play) => play.Status.State switch
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
        string? claimOrReason = play.Status.State switch
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
    public static string? Reason(this PlaySession play) => play.Status.EndReason switch
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

        // No reason is no words, in every language.
        _ => null,
    };

    /// <summary>The result notice's title, in whichever state it is standing.</summary>
    public static string? NoticeTitle(this PlaySession play) => play.Notice switch
    {
        ResultNotice.Recorded => Strings.Get("result.recorded"),
        ResultNotice.Result => play.Status.State switch
        {
            Mxq.MXQ_GAME_RED_WINS => Strings.Get("result.redWins"),
            Mxq.MXQ_GAME_BLACK_WINS => Strings.Get("result.blackWins"),
            Mxq.MXQ_GAME_DRAW => Strings.Get("result.draw"),
            _ => null,
        },
        _ => null,
    };

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
