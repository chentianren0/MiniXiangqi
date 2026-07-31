// The play screen, minus the window.
//
// Everything the board and the panel do is here: what a click on a point means,
// what the turn status says, which controls the mode offers, when the machine
// thinks and what happens when it answers. What is *not* here is XAML, because
// a Windows frontend that can only be exercised by a person looking at a screen
// can be exercised on no machine this project owns — an SSH session lands in
// session 0, which has no interactive desktop, and a WinUI 3 process fail-fasts
// there before any of this repository's code runs. So the screen's logic is a
// plain object over the core, the window drives it, and MiniXiangqi.Smoke plays
// whole games through it headlessly.
//
// Two rules hold over every line below.
//
//   * Nothing re-derives a rule. Legality, the legal-move set, whether a claim
//     or an undo or a resignation is available, how many plies a decision cycle
//     is, whether the game is over and why — every one of those is read from
//     the core (docs/architecture.md, and the repository's own note that the
//     shared core is the only place rules are decided).
//   * Everything runs on one thread. The store-attached active game's own
//     lifecycle and commits are the documented exception to
//     docs/core-interface.md's off-the-UI-thread rule, and they are the only
//     core calls made inline here. Engine preparation blocks and goes to a pool
//     thread; the search callback arrives on the core's engine thread. Both
//     come back through IPlayScheduler before touching anything below.

using System.Collections.Immutable;
using MiniXiangqi.Core;
using MiniXiangqi.Core.Interop;

namespace MiniXiangqi.Play;

/// <summary>What the turn status's AI activity slot is carrying.</summary>
public enum AiActivity
{
    /// <summary>Nothing at all: no search running, or one too young to show.</summary>
    Idle,

    /// <summary>A search has been running long enough to be worth an indicator.</summary>
    Thinking,

    /// <summary>
    /// The engine could not be prepared and the player chose 稍后, or it failed
    /// for a reason that is not memory. The game is saved and resumable; the
    /// retry lives here.
    /// </summary>
    Stalled,
}

/// <summary>Which blocking answer the screen is waiting for, if any.</summary>
public enum PlayAlert
{
    None,

    /// <summary>认输？ — it ends the game against the player and cannot be undone.</summary>
    Resign,

    /// <summary>局面已三次重复 — the claim is the player's own act to confirm.</summary>
    ClaimDraw,

    /// <summary>无法保存对局 — a terminal commit the store refused.</summary>
    SaveFailed,

    /// <summary>无法启动 AI 对手, in its mid-game form: the game is saved.</summary>
    EngineMemory,
}

/// <summary>What the result notice is showing.</summary>
public enum ResultNotice
{
    None,

    /// <summary>The result, unconfirmed. Both its actions save; the default only saves.</summary>
    Result,

    /// <summary>已记录到历史, where it stands, with the final board still under it.</summary>
    Recorded,
}

public sealed class PlaySession : IDisposable
{
    /// <summary>
    /// The AI activity indicator appears only once a search has run this long.
    /// One that arrives and leaves inside a third of a second reads as a
    /// flicker rather than as thinking. (Issue #71 decision, 2026-07-30; the
    /// same 400 ms the Apple frontend uses.)
    /// </summary>
    public static readonly TimeSpan ThinkingIndicatorDelay = TimeSpan.FromMilliseconds(400);

    private readonly MiniXiangqiCore _core;
    private readonly IPlayScheduler _scheduler;
    private readonly SearchService _search;

    /// <summary>
    /// Where the engine budget comes from. The platform probe in the app —
    /// <c>GlobalMemoryStatusEx</c>, per docs/engine-integration.md — and a
    /// supplied one in the harness, which is how the accepted mid-game
    /// insufficient-memory presentation is exercised on a machine that has
    /// plenty of memory. It is a probe rather than a plan, so the arithmetic
    /// under test is still the core's own.
    /// </summary>
    private readonly Func<MxqEngineBudget> _probe;

    private GameSession _game;
    private string _gameId;
    private GameConfiguration _configuration;

    private Placement _placement = Placement.Empty;
    private Square? _selected;
    private ImmutableHashSet<Square> _destinations = [];
    private ImmutableHashSet<Square> _captures = [];
    private Move? _lastMove;
    private Square? _checkedGeneral;
    private Square? _hovered;
    private bool _userFlipped;

    private IDisposable? _indicator;
    private Task? _preparation;
    private Task? _archive;
    private int _attempt;
    private bool _preparing;
    private bool _recorded;
    private RecordSummary? _committed;
    private bool _noticeDismissed;
    private Action? _failedCommit;

    public PlaySession(
        MiniXiangqiCore core,
        GameSession game,
        IPlayScheduler scheduler,
        Func<MxqEngineBudget>? probe = null)
    {
        _core = core;
        _game = game;
        _scheduler = scheduler;
        _probe = probe ?? WindowsMemoryProbe.Current;
        _search = new SearchService(core, scheduler);
        _gameId = game.Id;
        _configuration = game.Configuration();
        Read();
    }

    /// <summary>Raised on the scheduler's thread whenever anything above changed.</summary>
    public event Action? Changed;

    // What the screen shows.

    public BoardPosition Position { get; private set; }

    public GameState Status { get; private set; }

    /// <summary>
    /// The game's result, in <c>MxqGameState</c>'s vocabulary: the committed one
    /// once the game has been filed, and the position's own verdict before that.
    ///
    /// The two are not the same question and cannot be read from one place.
    /// <c>MxqGameStatus.state</c> is what the position on the board comes to,
    /// which is exactly right for a checkmate and says nothing at all about a
    /// resignation or a claimed draw — neither of those is a property of a
    /// position, and a game that ends by one of them stands on a board that is
    /// still somebody's to move. <c>mxq.h</c> names the second place: the
    /// committed outcome is <c>MxqOutcome</c>, and <c>mxq_store_history_get</c>
    /// is where it is read. So a terminal commit reads its own record back and
    /// this is what the screen says afterwards.
    /// </summary>
    public int ResultState { get; private set; }

    /// <summary>The reason beside it, from whichever of the two answered.</summary>
    public int ResultReason { get; private set; }

    public GameConfiguration Configuration => _configuration;

    public string GameId => _gameId;

    /// <summary>
    /// The move record: the core's own canonical coordinate text, live during
    /// play. Issue #80's trimmed scope makes this the Windows MVP's record in
    /// both languages — the 记谱法 preference and the two proper renderings
    /// arrive together post-MVP — so what is stored and what is shown are the
    /// same string here, and no formatter stands between them.
    /// </summary>
    public IReadOnlyList<string> MoveRecord { get; private set; } = [];

    /// <summary>
    /// The complete legal-move set in the current position, straight from the
    /// core. The screen itself never needs it — selection asks about one point
    /// — but the harnesses that drive whole games through this session do.
    /// </summary>
    public IReadOnlyList<string> LegalMoves() => _game.LegalMoves();

    public AiActivity Activity { get; private set; }

    public PlayAlert Alert { get; private set; }

    public ResultNotice Notice =>
        _noticeDismissed ? ResultNotice.None
        : _recorded ? ResultNotice.Recorded
        : IsOver ? ResultNotice.Result
        : ResultNotice.None;

    /// <summary>
    /// The one-ply save failure: a move or an Undo the store would not commit.
    /// The board is unchanged because the change did not happen, and the turn
    /// status says so. Cleared by the next action that succeeds.
    /// </summary>
    public bool MoveNotSaved { get; private set; }

    public BoardScene Scene { get; private set; } = BoardScene.Of(Placement.Empty);

    public bool IsHumanVersusAi => _configuration.Mode == Mxq.MXQ_PLAY_MODE_HUMAN_VS_AI;

    public Side? HumanSide => _configuration.HumanSide switch
    {
        Mxq.MXQ_COLOR_RED => Side.Red,
        Mxq.MXQ_COLOR_BLACK => Side.Black,
        _ => null,
    };

    public Side SideToMove => Position.SideToMove == Mxq.MXQ_COLOR_BLACK ? Side.Black : Side.Red;

    public bool IsOver => ResultState
        is Mxq.MXQ_GAME_RED_WINS or Mxq.MXQ_GAME_BLACK_WINS or Mxq.MXQ_GAME_DRAW;

    /// <summary>
    /// Whether this game has been filed. A filed game is immutable History and
    /// the active-game reference was cleared by the terminal commit that made
    /// it, so it is **not** an active game: the Play home's card does not
    /// describe it, and choosing a mode while it stands on the board presents no
    /// confirmation, because there is nothing left to save.
    /// </summary>
    public bool IsFiled => _recorded;

    /// <summary>
    /// In human-versus-AI play the human's own side is at the bottom and there
    /// is no flip control. Free Play starts with Red at the bottom and offers
    /// one.
    /// </summary>
    public bool Flipped => IsHumanVersusAi ? HumanSide == Side.Black : _userFlipped;

    public bool CanFlip => !IsHumanVersusAi;

    public bool CanUndo => Status.UndoAvailable && !_recorded;

    public bool CanClaimDraw => Status.ClaimAvailable && !_recorded;

    public bool CanResign => Status.ResignAvailable && !_recorded;

    /// <summary>
    /// Whether the board accepts input. It is refused before a piece moves
    /// rather than after: the committed game state is what decides, and while
    /// the AI is thinking or after a result the state is not the player's to
    /// change.
    /// </summary>
    public bool AcceptsInput =>
        !_recorded
        && Status.State is Mxq.MXQ_GAME_ONGOING or Mxq.MXQ_GAME_CLAIMABLE_DRAW
        && (!IsHumanVersusAi || SideToMove == HumanSide);

    // Starting.

    /// <summary>
    /// The game is on screen and whatever it owes is owed now: a created game
    /// whose resolved first mover is the AI, or a resumed one waiting on a
    /// reply it never got.
    /// </summary>
    public void Begin() => EnsureSearch();

    // Board input.

    /// <summary>
    /// A click on a point. The whole of the accepted move input, adapted to the
    /// pointer: selecting reveals every legal destination, a destination
    /// commits immediately, another of the player's own pieces switches the
    /// selection directly, the selected piece again cancels, and an illegal
    /// point moves nothing and cancels nothing.
    /// </summary>
    public void Tap(Square square)
    {
        if (!AcceptsInput)
        {
            return;
        }

        if (_selected is { } from)
        {
            if (from == square)
            {
                Select(null);
                return;
            }

            if (_destinations.Contains(square) || _captures.Contains(square))
            {
                Commit(new Move(from, square));
                return;
            }
        }

        if (_placement[square] is { } piece && piece.Side == SideToMove)
        {
            Select(square);
            return;
        }

        // An illegal point. The selection is retained: the answer belongs to
        // the piece the player is holding, and taking it away would answer a
        // question they did not ask. The accepted feedback — the legal-
        // destination markers pulsing once, or the turn status's acknowledgment
        // beat — is a one-shot animation and lands with the appearance pass;
        // see the pull request.
    }

    /// <summary>A click outside the board core cancels the selection.</summary>
    public void CancelSelection() => Select(null);

    /// <summary>
    /// Where the pointer is. It reports the device's position and never what is
    /// legal: a hover never previews a piece's destinations.
    /// </summary>
    public void Hover(Square? square)
    {
        if (_hovered == square)
        {
            return;
        }

        _hovered = square;
        Publish();
    }

    // Play controls.

    public void Undo()
    {
        if (!CanUndo)
        {
            return;
        }

        // What the machine is thinking about is about to stop being true.
        _search.Cancel();
        StopIndicator();
        Activity = AiActivity.Idle;

        if (!Mutate(() => _game.Undo()))
        {
            return;
        }

        // An Undo is the accepted way out of a stalled engine too: it returns
        // the game to the player's own decision point, where no search is owed.
        Select(null);
        Read();
        _noticeDismissed = false;
        Publish();
        EnsureSearch();
    }

    public void FlipBoard()
    {
        if (!CanFlip)
        {
            return;
        }

        _userFlipped = !_userFlipped;
        Publish();
    }

    /// <summary>认输 presents a confirmation, since it cannot be undone.</summary>
    public void RequestResign()
    {
        if (CanResign)
        {
            Alert = PlayAlert.Resign;
            Publish();
        }
    }

    /// <summary>
    /// 判和 presents the blocking notice. It never presents itself unbidden: it
    /// is the confirmation of the player's own act, and the standing offer is
    /// the enabled control together with the turn status's 可判和 line.
    /// </summary>
    public void RequestClaimDraw()
    {
        if (CanClaimDraw)
        {
            Alert = PlayAlert.ClaimDraw;
            Publish();
        }
    }

    public void DismissAlert()
    {
        Alert = PlayAlert.None;
        _failedCommit = null;
        Publish();
    }

    /// <summary>
    /// 认输, confirmed. It records a human loss and moves the game to immutable
    /// History.
    /// </summary>
    public void ConfirmResign() => Confirmed(() => CanResign, () => _game.Resign());

    /// <summary>以和棋结束, confirmed. The one finish that cannot be walked back.</summary>
    public void ConfirmClaimDraw() => Confirmed(() => CanClaimDraw, () => _game.ClaimDraw());

    /// <summary>
    /// 保存 — the result notice's default action. It confirms the result, files
    /// the game in History, and leaves the board standing exactly at the result
    /// it reached.
    /// </summary>
    public void SaveResult() => Confirmed(() => IsOver && !_recorded, () => _game.ConfirmResult());

    /// <summary>
    /// What every confirmed terminal act does before it acts: stop the machine
    /// thinking, and ask the core again whether the act it was asked about is
    /// still the act available.
    ///
    /// Both halves are necessary and neither is a precaution. The cancellation
    /// is a correctness requirement rather than a promptness one — a search
    /// outstanding over a game that has just ended answers to nothing, and a
    /// reply that survived to be applied would be applied to a detached,
    /// archived session, which is the programming-error class the core asserts
    /// on. And the re-check is necessary because a confirmation is not a
    /// barrier: a system dialog does not block the dispatcher, so between the
    /// question and the answer the AI's reply can land, the game can reach its
    /// own natural result, and the act can stop being available at all.
    /// Answering then is not a failure to report to anybody — the game ended
    /// while the player was reading — so it is a quiet return with the board
    /// brought up to date.
    /// </summary>
    private void Confirmed(Func<bool> stillAvailable, Func<ulong> commit)
    {
        _search.Cancel();
        StopIndicator();
        Activity = AiActivity.Idle;
        Read();

        if (Alert is PlayAlert.Resign or PlayAlert.ClaimDraw)
        {
            Alert = PlayAlert.None;
        }

        if (!stillAvailable())
        {
            Publish();
            return;
        }

        Terminal(commit);
    }

    /// <summary>重试, for a terminal commit the store refused.</summary>
    public void RetryFailedCommit()
    {
        Action? retry = _failedCommit;
        _failedCommit = null;
        Alert = PlayAlert.None;
        retry?.Invoke();
    }

    /// <summary>
    /// What every concluding action does first: file the game if it is not
    /// filed already, and answer whether it is filed now.
    ///
    /// A claimed draw arrives already recorded and so does a result the player
    /// has saved, and neither is filed twice — that is what the guard inside
    /// <see cref="SaveResult"/> is. A filing the store refuses answers false
    /// with the accepted 无法保存对局 retry up, and the caller does nothing
    /// further: the game stays active and exactly as it stood.
    ///
    /// What happens *after* the filing is the destination's, not this screen's.
    /// docs/interaction-design.md, "Where the concluding actions go": 开始新对局
    /// opens that game's own mode's pre-start state and 完成 returns to the Play
    /// home, and neither of those is something a board knows how to do.
    /// </summary>
    public bool FileIfNeeded()
    {
        if (!_recorded)
        {
            SaveResult();
        }

        return _recorded;
    }

    /// <summary>
    /// Stop the machine thinking, because what it is thinking about is about to
    /// stop being true. Public because 保存并继续 is a decision taken on another
    /// page about this game: a search outstanding over a game that is being
    /// archived answers to nothing.
    /// </summary>
    public void CancelSearch()
    {
        _search.Cancel();
        StopIndicator();
        Activity = AiActivity.Idle;
        Publish();
    }

    /// <summary>
    /// **保存并继续**'s archive: the active game filed by its factual current
    /// state and the active-game reference cleared, atomically.
    ///
    /// It is the one operation on this path that is **not** driven from the UI
    /// thread — docs/core-interface.md's threading contract keeps
    /// <c>mxq_store_archive_and_clear</c> outside the main-actor exception the
    /// active game's own commits run under — so the session goes to a pool
    /// thread and the answer comes back through the scheduler. Nothing may enter
    /// this session in between, which is what the caller's own guard is for: a
    /// session is single-owner by contract, and a detected race is
    /// MXQ_ERR_ARG_CONCURRENT_USE rather than a silent serialisation.
    ///
    /// The search is cancelled first, here, so that the caller cannot forget to.
    /// </summary>
    public void ArchiveAndClear(Action<MxqException?> answered)
    {
        CancelSearch();
        GameSession game = _game;
        _archive = Task.Run(() =>
        {
            MxqException? failure = null;
            try
            {
                _core.ArchiveAndClear(game);
            }
            catch (MxqException caught)
            {
                failure = caught;
            }

            _scheduler.Post(() => answered(failure));
        });
    }

    /// <summary>
    /// The notice is dismissible — by its own close control, by the platform's
    /// cancel key, or by a click on the board — and it does not present itself
    /// again for the same result. Closing it decides nothing: the result is
    /// still carried by the turn status, and the concluding action is still
    /// carried by the play-control cluster.
    /// </summary>
    public void DismissNotice()
    {
        _noticeDismissed = true;
        Publish();
    }

    // The engine.

    /// <summary>重试, from the alert or from the turn status's stalled slot.</summary>
    public void RetryEngine()
    {
        Alert = PlayAlert.None;
        Activity = AiActivity.Idle;
        Publish();
        EnsureSearch();
    }

    /// <summary>
    /// 稍后. The alert goes away and the stalled state moves to where
    /// things-about-the-game live, carrying its own retry.
    /// </summary>
    public void DeferEngine()
    {
        Alert = PlayAlert.None;
        if (!_preparing && _search.Ticket is null)
        {
            Activity = Status.SearchExpected ? AiActivity.Stalled : AiActivity.Idle;
        }

        Publish();
    }

    /// <summary>
    /// Quiesce and release. docs/core-interface.md's shutdown promise covers
    /// every call that *begins* after <c>mxq_core_shutdown</c> returns, and
    /// explicitly not one already in flight on another thread — "the caller
    /// quiesces its own threads before shutting the core down; the core does
    /// not defend against one that does not." An engine preparation and an
    /// archive are this session's only calls on another thread, so both are
    /// waited for here. Each wait is bounded by that call's own completion and
    /// cannot deadlock: they run on pool threads and depend on nothing this
    /// thread holds.
    /// </summary>
    public void Dispose()
    {
        StopIndicator();
        _search.Dispose();
        Quiesce(_preparation);
        Quiesce(_archive);
        _preparation = null;
        _archive = null;
        _game.Dispose();
    }

    private static void Quiesce(Task? work)
    {
        try
        {
            work?.Wait();
        }
        catch (AggregateException)
        {
            // The call's own failure was already reported through the scheduler,
            // or will never be delivered because the window is closing. Either
            // way there is nobody left to tell.
        }
    }

    // Reading the core.

    private void Read()
    {
        Position = _game.Position();
        Status = _game.State();
        ResultState = _committed is { } record ? StateOf(record.Outcome) : Status.State;
        ResultReason = _committed is { } filed ? filed.EndReason : Status.EndReason;
        _placement = new Placement(Position.Fen);
        MoveRecord = _game.MoveHistory();
        _lastMove = MoveRecord.Count > 0 ? Move.Parse(MoveRecord[^1]) : null;
        _checkedGeneral = Position.InCheck ? _placement.General(SideToMove) : null;
        Compose();
    }

    private void Select(Square? square)
    {
        if (square is { } point && AcceptsInput)
        {
            _selected = point;
            _destinations = [];
            _captures = [];
            ImmutableHashSet<Square>.Builder empty = ImmutableHashSet.CreateBuilder<Square>();
            ImmutableHashSet<Square>.Builder taken = ImmutableHashSet.CreateBuilder<Square>();
            foreach (string text in _game.LegalMovesFrom(point.Name))
            {
                if (Move.Parse(text) is not { } move)
                {
                    continue;
                }

                if (_placement[move.To] is not null)
                {
                    taken.Add(move.To);
                }
                else
                {
                    empty.Add(move.To);
                }
            }

            _destinations = empty.ToImmutable();
            _captures = taken.ToImmutable();
        }
        else
        {
            _selected = null;
            _destinations = [];
            _captures = [];
        }

        Compose();
        Publish();
    }

    private void Compose()
    {
        // A held general's check rings hide, because the selection ring and the
        // check rings occupy the same band and cannot both be drawn; the turn
        // status's 将军 token carries the state through the gap.
        Square? checkedGeneral = _checkedGeneral == _selected ? null : _checkedGeneral;

        Scene = new BoardScene
        {
            Placement = _placement,
            Flipped = Flipped,
            Selected = _selected,
            Destinations = _destinations,
            Captures = _captures,
            LastMove = _lastMove,
            CheckedGeneral = checkedGeneral,
            Hovered = _hovered,
        };
    }

    private void Publish()
    {
        Compose();
        Changed?.Invoke();
    }

    // Committing.

    private void Commit(Move move)
    {
        if (!Mutate(() => _game.ApplyMove(move.Text)))
        {
            return;
        }

        Select(null);
        Read();
        Publish();
        EnsureSearch();
    }

    /// <summary>
    /// Runs one committing call, and answers whether it committed. A
    /// store-domain failure leaves the game exactly at its pre-mutation state,
    /// so the move or the Undo did not happen: the board is unchanged, the turn
    /// status says the change could not be saved, and the user may simply try
    /// again. Nothing else is caught — a rules-domain refusal here would be a
    /// bug in this file rather than an answer to the player.
    /// </summary>
    private bool Mutate(Action call)
    {
        try
        {
            call();
            MoveNotSaved = false;
            return true;
        }
        catch (MxqException failure) when (failure.Domain == Mxq.MXQ_DOMAIN_STORE)
        {
            MoveNotSaved = true;
            Publish();
            return false;
        }
    }

    /// <summary>
    /// One of the three terminal commits. Each is one atomic transaction: the
    /// outcome is committed, the immutable History record inserted, and the
    /// active-game reference cleared. On a store-domain failure the game
    /// remains active and unchanged, and the accepted 无法保存对局 retry says so.
    /// </summary>
    private bool Terminal(Func<ulong> commit)
    {
        ulong record;
        try
        {
            record = commit();
        }
        catch (MxqException failure) when (failure.Domain == Mxq.MXQ_DOMAIN_STORE)
        {
            Alert = PlayAlert.SaveFailed;
            _failedCommit = () => Terminal(commit);
            Publish();
            return false;
        }
        catch (MxqException failure) when (failure.Domain == Mxq.MXQ_DOMAIN_STATE)
        {
            // A state-domain refusal here says the act is no longer the act
            // available — the game already has a result, or the session is
            // already archived. The guard above asked a moment ago and the core
            // said yes; whatever changed between then and now is not the
            // player's mistake and there is nothing to tell them that the board
            // will not say. So the board is brought up to date and nothing else
            // happens. It is deliberately not an escape: this runs under a
            // dialog's completion, and an exception from there would reach the
            // application's own unhandled handler rather than any caller.
            Read();
            Publish();
            return false;
        }

        _recorded = true;

        // Read the record back, because the committed classification is the
        // core's and this is where the core keeps it. It is one row by
        // identifier — strictly less work than the terminal commit that just
        // ran under the active game's own UI-thread exception, committing
        // nothing and touching one index — so it is read here rather than
        // marshalled, which would leave the screen showing the wrong result for
        // a frame.
        _committed = _core.HistoryRecord(record);

        _noticeDismissed = false;
        Alert = PlayAlert.None;
        Select(null);
        Read();
        Publish();
        return true;
    }

    /// <summary>
    /// A committed outcome, said in the vocabulary the screen already speaks.
    /// It is a translation between two of the core's own parallel vocabularies,
    /// both frozen in game-data.md, and not an adjudication: nothing here
    /// decides who won, it only says the same answer in the other set of words.
    /// <c>MXQ_OUTCOME_NONE</c> belongs to a game ended early, which this screen
    /// never files.
    /// </summary>
    private static int StateOf(int outcome) => outcome switch
    {
        Mxq.MXQ_OUTCOME_RED_WINS => Mxq.MXQ_GAME_RED_WINS,
        Mxq.MXQ_OUTCOME_BLACK_WINS => Mxq.MXQ_GAME_BLACK_WINS,
        Mxq.MXQ_OUTCOME_DRAW => Mxq.MXQ_GAME_DRAW,
        _ => Mxq.MXQ_GAME_ONGOING,
    };

    // The machine on the other side of the board.

    private void EnsureSearch()
    {
        if (!IsHumanVersusAi || _recorded)
        {
            return;
        }

        if (!Status.SearchExpected)
        {
            // Nothing is owed, so nothing is shown: a stalled slot must not
            // outlive its own reason.
            if (Activity != AiActivity.Idle)
            {
                Activity = AiActivity.Idle;
                Publish();
            }

            return;
        }

        if (_preparing || _search.Ticket is not null
            || Activity == AiActivity.Stalled || Alert == PlayAlert.EngineMemory)
        {
            return;
        }

        if (_core.Engine.State == Mxq.MXQ_ENGINE_STATE_READY)
        {
            StartSearch();
        }
        else
        {
            PrepareThenSearch();
        }
    }

    private void PrepareThenSearch()
    {
        _preparing = true;
        int token = ++_attempt;

        // A fresh probe at every attempt: a retry that follows a refusal has to
        // see the memory the user just freed, and a cached value would answer
        // with the state that produced the refusal.
        MxqEngineBudget budget = _probe();

        // mxq_engine_prepare blocks — it allocates Hash and loads the network,
        // marshalled onto the engine thread — and the threading contract keeps
        // it off the UI thread. So it goes to a pool thread and the answer
        // comes back through the scheduler. The task is kept, because the same
        // contract puts quiescence on the caller: a core shut down with a
        // prepare still in flight is a call already inside the core when the
        // gate closes, and the core does not defend against one.
        _preparation = Task.Run(() =>
        {
            MxqException? failure = null;
            try
            {
                _core.PrepareEngine(budget);
            }
            catch (MxqException caught)
            {
                failure = caught;
            }

            _scheduler.Post(() =>
            {
                if (token != _attempt)
                {
                    return;
                }

                _preparing = false;
                if (failure is null)
                {
                    EnsureSearch();
                }
                else
                {
                    Report(failure);
                }
            });
        });
    }

    private void StartSearch()
    {
        if (_configuration.MovetimeMs == 0)
        {
            return;
        }

        int token = ++_attempt;
        try
        {
            _search.Start(_game, _configuration.MovetimeMs, answer => Answered(answer, token));
        }
        catch (MxqException failure)
        {
            // The one refusal with an answer of its own: the engine was torn
            // down under the search, so it is prepared again, because a search
            // is owed.
            if (failure.Status == Mxq.MXQ_ERR_ENGINE_NOT_PREPARED)
            {
                PrepareThenSearch();
            }
            else
            {
                Report(failure);
            }

            return;
        }

        StopIndicator();
        _indicator = _scheduler.After(ThinkingIndicatorDelay, () =>
        {
            if (token != _attempt || _search.Ticket is null)
            {
                return;
            }

            Activity = AiActivity.Thinking;
            Publish();
        });
    }

    private void Answered(SearchAnswer answer, int token)
    {
        if (token != _attempt)
        {
            return;
        }

        StopIndicator();
        Activity = AiActivity.Idle;

        // A game that has been filed is nobody's to answer. A terminal commit
        // archives the session without changing the position, so the staleness
        // comparison below would let this reply through; this is what stops it.
        if (_recorded)
        {
            Publish();
            return;
        }

        switch (answer.Outcome)
        {
            case Mxq.MXQ_SEARCH_MOVE:
                // The frontend's own staleness comparison, which the interface
                // requires in addition to the core's: the core compares before
                // delivery and this compares before applying, and neither alone
                // covers both race directions.
                if (answer.GameId != _gameId
                    || answer.PositionRevision != Position.PositionRevision
                    || Move.Parse(answer.Move) is not { } move)
                {
                    Publish();
                    return;
                }

                ApplyOpponent(move);
                return;

            case Mxq.MXQ_SEARCH_CANCELLED:
            case Mxq.MXQ_SEARCH_STALE:
                // Whoever cancelled decides what happens next, and a stale
                // result is one the position has already left behind.
                Publish();
                return;

            default:
                if (answer.Status == Mxq.MXQ_ERR_ENGINE_NOT_PREPARED)
                {
                    Publish();
                    EnsureSearch();
                    return;
                }

                // The engine produced nothing this game can use. The game is
                // untouched, saved and resumable, and the slot says the one
                // thing true of every such failure — the AI cannot start right
                // now — with the retry beside it. Deliberately not the
                // insufficient-memory alert: that alert names a cause, and
                // naming the wrong cause is worse than naming none.
                Activity = AiActivity.Stalled;
                Publish();
                return;
        }
    }

    private void ApplyOpponent(Move move)
    {
        try
        {
            _game.ApplyMove(move.Text);
        }
        catch (MxqException failure) when (failure.Domain == Mxq.MXQ_DOMAIN_STORE)
        {
            // A failed save of the AI's reply shows nothing at all: the retry
            // is the app's, not the user's. The game is at the last committed
            // position with the AI still to move, so a new search is requested
            // from it rather than the same result being pushed again.
            Publish();
            EnsureSearch();
            return;
        }
        catch (MxqException failure) when (failure.Domain == Mxq.MXQ_DOMAIN_STATE)
        {
            // The game stopped being this reply's to answer — it was resigned,
            // claimed or confirmed while the reply was in the air. The staleness
            // comparison above cannot see that, because a terminal commit is not
            // a position change: it archives the session at the same revision.
            // So the board is brought up to date and the reply is dropped, which
            // is what a search outstanding over a game that has just ended is
            // worth.
            Read();
            Publish();
            return;
        }

        Read();
        _noticeDismissed = false;
        Publish();
        EnsureSearch();
    }

    /// <summary>
    /// What the player is told about an engine failure mid-game, by code.
    /// Only the memory failure is the accepted 无法启动 AI 对手 situation.
    /// Everything else the engine can refuse with — a network missing or
    /// mismatched, a variant that would not load, a faulted engine — is a
    /// damaged installation rather than a busy machine, and it takes the
    /// stalled slot with no cause named.
    /// </summary>
    private void Report(MxqException failure)
    {
        if (failure.Status == Mxq.MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY)
        {
            Alert = PlayAlert.EngineMemory;
        }
        else
        {
            Activity = AiActivity.Stalled;
        }

        Publish();
    }

    private void StopIndicator()
    {
        _indicator?.Dispose();
        _indicator = null;
    }
}
