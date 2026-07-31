using System.Text;
using Microsoft.UI.Xaml;
using MiniXiangqi.Core;
using MiniXiangqi.Core.Interop;

namespace MiniXiangqi.App;

/// <summary>
/// The proof-of-life view: the core's four version axes, the active game's
/// position and derived state, its legal moves, and its retained line — all
/// read back from the core rather than computed here.
///
/// Every core call below is one the threading contract's documented exception
/// covers: <c>mxq_core_init</c> is a UI-or-setup-thread call, and the
/// store-attached active game's own lifecycle and commits may be driven
/// synchronously from the UI thread. Nothing else is called from here.
/// </summary>
public sealed partial class MainWindow : Window
{
    private readonly MiniXiangqiCore? _core;
    private readonly GameSession? _session;

    public MainWindow()
    {
        InitializeComponent();

        string assets = Path.Combine(AppContext.BaseDirectory, "assets");
        string store = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "MiniXiangqi",
            "skeleton-store");

        Subtitle.Text = $"Store {store}\nAssets {assets}";
        ShowBuild();

        try
        {
            _core = MiniXiangqiCore.Start(store, assets);
            _session = _core.ResumeOrCreate(
                humanSide: Mxq.MXQ_COLOR_RED,
                aiLevel: Mxq.MXQ_AI_LEVEL_FAST,
                firstMoverChoice: Mxq.MXQ_FIRST_MOVER_HUMAN_FIRST,
                movetimeMs: Mxq.MXQ_MOVETIME_FAST_MS);
            Refresh();
        }
        catch (MxqException ex)
        {
            ShowProblem(ex);
        }

        Closed += (_, _) =>
        {
            _session?.Dispose();
            _core?.Dispose();
        };
    }

    private void OnPlayFirstLegalMove(object sender, RoutedEventArgs e)
    {
        if (_session is null)
        {
            return;
        }

        try
        {
            IReadOnlyList<string> moves = _session.LegalMoves();
            if (moves.Count == 0)
            {
                return;
            }

            _session.ApplyMove(moves[0]);
            Problem.IsOpen = false;
            Refresh();
        }
        catch (MxqException ex)
        {
            ShowProblem(ex);
        }
    }

    private void ShowBuild()
    {
        CoreVersion version = MiniXiangqiCore.Version;
        StringBuilder text = new();
        text.AppendLine($"api             {version.ApiVersion}");
        text.AppendLine($"archive         current {version.ArchiveVersionCurrent}, min readable {version.ArchiveVersionMinReadable}");
        text.AppendLine($"store schema    {version.StoreSchemaVersion}");
        text.AppendLine($"core revision   {version.CoreRevision}");
        text.AppendLine($"fork revision   {version.ForkRevision}");
        text.AppendLine($"variant         {version.VariantId}");
        text.Append($"nnue sha256     {version.NnueSha256}");
        BuildLines.Text = text.ToString();
    }

    private void Refresh()
    {
        if (_session is null)
        {
            return;
        }

        BoardPosition position = _session.Position();
        GameState state = _session.State();

        StringBuilder text = new();
        text.AppendLine($"game id         {_session.Id}");
        text.AppendLine($"fen             {position.Fen}");
        text.AppendLine($"side to move    {Describe(position.SideToMove)}");
        text.AppendLine($"ply             {position.PlyCount}");
        text.AppendLine($"revision        {position.PositionRevision}");
        text.AppendLine($"in check        {position.InCheck}");
        text.AppendLine($"state / reason  {state.State} / {state.EndReason}");
        text.Append($"affordances     claim {state.ClaimAvailable}, undo {state.UndoAvailable} ({state.UndoPlies} ply), resign {state.ResignAvailable}, search expected {state.SearchExpected}");
        PositionLines.Text = text.ToString();

        IReadOnlyList<string> legal = _session.LegalMoves();
        LegalMoveLines.Text = legal.Count == 0
            ? "(none)"
            : $"{legal.Count}: {string.Join(' ', legal)}";

        IReadOnlyList<string> history = _session.MoveHistory();
        HistoryLines.Text = history.Count == 0
            ? "(none)"
            : $"{history.Count}: {string.Join(' ', history)}";

        PlayFirstLegalMove.IsEnabled = legal.Count > 0;
    }

    private void ShowProblem(MxqException ex)
    {
        // The status name and the diagnostic, not user-facing copy: the
        // designed presentation for each domain is a later pull request, and
        // showing a draft of it here would be inventing one.
        Problem.Message = $"{ex.StatusName} ({ex.Status}), domain {ex.Domain}\n{ex.Detail}";
        Problem.IsOpen = true;
    }

    private static string Describe(int color) => color switch
    {
        Mxq.MXQ_COLOR_RED => "red",
        Mxq.MXQ_COLOR_BLACK => "black",
        _ => "none",
    };
}
