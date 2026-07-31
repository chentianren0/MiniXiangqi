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
    private int _attempt;
    private bool _preparing;
    private bool _recorded;
    private bool _noticeDismissed;
    private Action? _failedCommit;

    public PlaySession(MiniXiangqiCore core, GameSession game, IPlayScheduler scheduler)
    {
        _core = core;
        _game = game;
        _scheduler = scheduler;
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

    public bool IsOver => Status.State
        is Mxq.MXQ_GAME_RED_WINS or Mxq.MXQ_GAME_BLACK_WINS or Mxq.MXQ_GAME_DRAW;

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

    public void ConfirmResign() => Terminal(() => _game.Resign());

    public void ConfirmClaimDraw()
    {
        // Claiming while the AI is thinking is legal exactly when the core
        // reports the claim available; the search is cancelled before the
        // terminal commit, because a search outstanding over a game that has
        // just ended answers to nothing.
        _search.Cancel();
        StopIndicator();
        Activity = AiActivity.Idle;
        Terminal(() => _game.ClaimDraw());
    }

    /// <summary>
    /// 保存 — the result notice's default action. It confirms the result, files
    /// the game in History, and leaves the board standing exactly at the result
    /// it reached.
    /// </summary>
    public void SaveResult() => Terminal(() => _game.ConfirmResult());

    /// <summary>重试, for a terminal commit the store refused.</summary>
    public void RetryFailedCommit()
    {
        Action? retry = _failedCommit;
        _failedCommit = null;
        Alert = PlayAlert.None;
        retry?.Invoke();
    }

    /// <summary>
    /// The concluding action: 开始新对局 on the play-control cluster, and
    /// 保存并开始新对局 on the notice. It files the finished game and resets the
    /// board, and no confirmation stands between it and the new game.
    /// </summary>
    public void NewGame()
    {
        if (!_recorded && IsOver && !Terminal(() => _game.ConfirmResult()))
        {
            return;
        }

        if (!_recorded)
        {
            return;
        }

        GameSession replacement = _core.Create(
            _configuration.Mode,
            _configuration.HumanSide,
            _configuration.AiLevel,
            _configuration.FirstMoverChoice,
            _configuration.MovetimeMs);

        _game.Dispose();
        _game = replacement;
        _gameId = replacement.Id;
        _configuration = replacement.Configuration();
        _recorded = false;
        _noticeDismissed = false;
        MoveNotSaved = false;
        Select(null);
        Read();
        Publish();
        EnsureSearch();
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

    public void Dispose()
    {
        StopIndicator();
        _search.Dispose();
        _game.Dispose();
    }

    // Reading the core.

    private void Read()
    {
        Position = _game.Position();
        Status = _game.State();
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
        try
        {
            commit();
        }
        catch (MxqException failure) when (failure.Domain == Mxq.MXQ_DOMAIN_STORE)
        {
            Alert = PlayAlert.SaveFailed;
            _failedCommit = () => Terminal(commit);
            Publish();
            return false;
        }

        _recorded = true;
        _noticeDismissed = false;
        Alert = PlayAlert.None;
        Select(null);
        Read();
        Publish();
        return true;
    }

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
        MxqEngineBudget budget = WindowsMemoryProbe.Current();

        // mxq_engine_prepare blocks — it allocates Hash and loads the network,
        // marshalled onto the engine thread — and the threading contract keeps
        // it off the UI thread. So it goes to a pool thread and the answer
        // comes back through the scheduler.
        Task.Run(() =>
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
