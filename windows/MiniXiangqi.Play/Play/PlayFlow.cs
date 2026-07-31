// The Play destination: three pages, the game that outlives them, and every
// path between them.
//
// This is the flows pull request's answer to the seam MainWindow carried since
// the play screen merged — "the setup screen and the Play home arrive in the
// next pull request. Until they do, this window resumes the single active game
// or creates one exactly as the walking skeleton did". It replaces that, and it
// lives here rather than in the window for the reason every other piece of this
// frontend's behaviour does: a WinUI 3 process cannot be launched over SSH, so
// anything inside the window can be exercised on no machine this project owns.
// MiniXiangqi.Smoke drives all of this headlessly.
//
// docs/interaction-design.md, "Navigation": Play has pages of its own. Its root
// is the Play home, where what to play is chosen; each mode's pre-start state
// and the board are pages over it, reached by choosing and left by a back
// control. Leaving the board for the home ends nothing — the game stays active
// and the home's own card is the way back into it — and a launch with a game to
// resume opens **at the board**, not at the home.
//
// docs/interaction-design.md, "Starting and configuring a game": a game is
// created by 开始对局 and by nothing else; the pre-start controls are an
// in-memory draft initialized afresh from the Settings defaults on every entry;
// with any active game, selecting either mode presents the one save-and-continue
// confirmation instead of opening anything.
//
// docs/engine-integration.md, "Accepted preparation ordering": human-versus-AI
// creation runs prepare → resolve → create → search, each step a gate on the
// next, from a fresh memory probe every attempt.
//
// **The game lives here rather than on the board page**, and that placement is
// the whole point of this type. The board is one of three pages; walking to the
// home and back must not resume the game again, must not re-decode the stored
// line, and must not bring back a result notice the player has already put away.

using MiniXiangqi.Core;
using MiniXiangqi.Core.Interop;

namespace MiniXiangqi.Play;

/// <summary>Which of the destination's three pages is showing.</summary>
public enum PlayPage
{
    /// <summary>What to play, and the active game if there is one. No board on it.</summary>
    Home,

    /// <summary>That mode's pre-start state, over a noninteractive preview.</summary>
    Setup,

    /// <summary>The board.</summary>
    Board,
}

/// <summary>Which blocking answer the destination is waiting for, if any.</summary>
public enum FlowAlert
{
    None,

    /// <summary>
    /// 开始新对局？ — the one save-and-continue confirmation, for every
    /// combination of old mode, new mode and active-game state.
    /// </summary>
    NewGame,

    /// <summary>无法保存对局 — the archive the store refused. The game is unchanged.</summary>
    ArchiveFailed,

    /// <summary>
    /// 无法启动 AI 对手, in its pre-start form: there is no game to keep, so its
    /// actions are 取消 and 重试 and its message carries no saved-game guarantee.
    /// </summary>
    AiUnavailable,

    /// <summary>无法开始对局 — a creation the store would not persist.</summary>
    GameNotStarted,
}

public sealed class PlayFlow : IDisposable
{
    private readonly MiniXiangqiCore _core;
    private readonly IPlayScheduler _scheduler;
    private readonly IPreferenceStore _preferences;
    private readonly Func<MxqEngineBudget> _probe;

    private PlaySession? _session;
    private Placement? _preview;

    /// <summary>
    /// The mode the player asked for while a game was active. It is remembered
    /// only while the confirmation or its retry exists, which is the accepted
    /// rule — "the requested destination remains temporary only while this
    /// confirmation or retry flow exists" — and there is nowhere here for it to
    /// survive them.
    /// </summary>
    private PlayMode? _requested;

    /// <summary>
    /// True between 保存并继续 and the archive answering. It is not the same as
    /// the confirmation being up: the confirmation is gone by then, and what
    /// this stops is a second archive of a game the first one is inside.
    /// </summary>
    private bool _saving;

    /// <summary>
    /// The creation attempt in flight, and the invalidation of every earlier
    /// one. Leaving the pre-start state bumps it, which is what stops a late
    /// completion from committing after the draft is discarded.
    /// </summary>
    private int _attempt;

    /// <summary>
    /// The archive in flight, and the invalidation of it. Disposal bumps it, so
    /// a completion posted after this object has let go of its game decides
    /// nothing — which is the check the Apple frontend makes by re-reading its
    /// own mode-switch state inside the same callback.
    /// </summary>
    private int _archiveAttempt;

    /// <summary>
    /// Every engine preparation still in flight, not merely the newest.
    ///
    /// A single field would be wrong, and reachably so: leaving the pre-start
    /// page mid-preparation, re-entering it and pressing **开始对局** again puts
    /// two <c>mxq_engine_prepare</c> calls in flight at once — the first
    /// attempt's is not cancelled, only disowned — and a field would leave
    /// disposal waiting on the newer one alone. Closing the window then shuts
    /// the core down with the older call still inside it, which is precisely
    /// what docs/core-interface.md's shutdown promise says the core does not
    /// defend against: "the caller quiesces its own threads before shutting the
    /// core down".
    ///
    /// Only ever touched on this object's own thread: added to in
    /// <see cref="StartGame"/> and drained in <see cref="Dispose"/>.
    /// </summary>
    private readonly List<Task> _preparations = [];

    private bool _started;

    public PlayFlow(
        MiniXiangqiCore core,
        IPlayScheduler scheduler,
        IPreferenceStore? preferences = null,
        Func<MxqEngineBudget>? probe = null)
    {
        _core = core;
        _scheduler = scheduler;
        _preferences = preferences ?? new FilePreferenceStore();
        _probe = probe ?? WindowsMemoryProbe.Current;
        Draft = SetupDraft.FromDefaults(_preferences);
    }

    /// <summary>Raised on the scheduler's thread whenever anything below changed.</summary>
    public event Action? Changed;

    public PlayPage Page { get; private set; } = PlayPage.Home;

    /// <summary>Which mode's pre-start page <see cref="PlayPage.Setup"/> is.</summary>
    public PlayMode SetupMode { get; private set; }

    /// <summary>
    /// The game on the board, filed or not. Null before the first game of a
    /// launch that resumed nothing, and again after every release.
    /// </summary>
    public PlaySession? Session => _session;

    /// <summary>
    /// The game the store still holds — the one the home's card is about, and
    /// the one the save-and-continue confirmation would archive.
    ///
    /// A game that has been filed is not one of them. Its record is immutable
    /// History and the active-game reference was cleared by the terminal commit
    /// that made it; what stands on the board afterwards is the result where it
    /// was reached, which is presentation.
    /// </summary>
    public PlaySession? ActiveGame => _session is { IsFiled: false } live ? live : null;

    /// <summary>
    /// The 当前对局 card's line: the same metadata the confirmation puts under
    /// the same header. Null where there is no active game to describe.
    /// </summary>
    public string? ActiveGameLine => ActiveGame?.MetadataLine();

    /// <summary>
    /// The pre-start controls' draft. Meaningful only on the setup page, and
    /// replaced afresh on every entry to it.
    /// </summary>
    public SetupDraft Draft { get; private set; }

    /// <summary>
    /// Whether a creation attempt is in flight. **开始对局** cannot be invoked
    /// again while it is.
    /// </summary>
    public bool Creating { get; private set; }

    public FlowAlert Alert { get; private set; }

    /// <summary>
    /// What the setup page's preview draws: the frozen initial position, never
    /// interactive, with the human's own side at the bottom. **随机** remains
    /// unresolved and previews Red.
    /// </summary>
    public BoardScene PreviewScene => new()
    {
        Placement = _preview ??= new Placement(MiniXiangqiCore.StartFen),
        Flipped = SetupMode == PlayMode.HumanVersusAi && Draft.PreviewsHumanAsBlack,
    };

    // MARK: Launch.

    /// <summary>
    /// Opens the game the library holds, or the home when it holds none.
    ///
    /// Launch is a resume, and a resumed human-versus-AI game owing a move
    /// prepares and searches for it exactly as a fresh one would. A launch that
    /// has a game to open goes straight to the board rather than by way of the
    /// home, which is the accepted resume-at-launch behaviour and is what the
    /// home being a navigable root has to leave untouched.
    ///
    /// It creates nothing. A game is created by 开始对局 and by nothing else,
    /// which is exactly what the seam this replaces did not honour.
    /// </summary>
    public void Start()
    {
        if (_started)
        {
            return;
        }

        _started = true;
        if (_core.ResumeActive() is { } resumed)
        {
            Adopt(resumed);
            Page = PlayPage.Board;
            Publish();
            _session!.Begin();
            return;
        }

        Page = PlayPage.Home;
        Publish();
    }

    // MARK: The home.

    /// <summary>
    /// A mode entry was chosen on the home.
    ///
    /// With no active game it opens that mode's pre-start page. With one it
    /// opens nothing at all: the accepted confirmation presents instead, and the
    /// destination waits inside it. A game already filed is neither — it is a
    /// History record the board was still showing, so it is let go of here and
    /// the pre-start page opens as it would have with no game at all.
    /// </summary>
    public void Choose(PlayMode mode)
    {
        if (Page != PlayPage.Home || Alert != FlowAlert.None || _saving)
        {
            return;
        }

        if (ActiveGame is not null)
        {
            _requested = mode;
            Alert = FlowAlert.NewGame;
            Publish();
            return;
        }

        Release();
        OpenSetup(mode);
    }

    /// <summary>
    /// **回到对局** on the home's current-game card: the board, and the game
    /// exactly as it was left.
    ///
    /// Not while a mode switch is anywhere in it. Both of that flow's alerts
    /// belong to the home, so leaving the page with an archive in flight would
    /// leave a refusal with no page to present the accepted 无法保存对局 retry
    /// on — and a success would take the player off the board they had just
    /// asked for and onto a pre-start page they never asked to see.
    /// </summary>
    public void Resume()
    {
        if (Page != PlayPage.Home || Alert != FlowAlert.None || _saving || ActiveGame is null)
        {
            return;
        }

        Page = PlayPage.Board;
        Publish();
    }

    /// <summary>
    /// **取消**, on either of the home's alerts and on either of the pre-start
    /// page's.
    ///
    /// On the confirmation and on its retry it discards the remembered
    /// destination and leaves the active game completely unchanged — it can be
    /// resumed and taken back or claimed on the board, as it always could. On a
    /// creation failure it dismisses without leaving the page, so the draft is
    /// still there and **开始对局** is on offer again.
    /// </summary>
    public void DismissAlert()
    {
        if (Alert is FlowAlert.NewGame or FlowAlert.ArchiveFailed)
        {
            _requested = null;
        }

        Alert = FlowAlert.None;
        Publish();
    }

    /// <summary>
    /// **保存并继续**, and the **重试** that repeats it.
    ///
    /// The archive is one atomic core call and the classification inside it is
    /// entirely the core's: an ordinary ongoing game and an unclaimed claimable
    /// repetition are recorded as ended early, and an unconfirmed natural
    /// terminal keeps its actual result and its exact reason. Only when it has
    /// committed does the selected mode's pre-start page open, and no new game
    /// exists until **开始对局** succeeds there.
    ///
    /// A refusal commits nothing: the old game is still active, still exactly as
    /// it stood, and the accepted retry presents over it.
    /// </summary>
    public void SaveAndContinue()
    {
        if (_requested is not { } mode || ActiveGame is not { } live || _saving)
        {
            return;
        }

        _saving = true;
        Alert = FlowAlert.None;
        int token = ++_archiveAttempt;
        Publish();

        // Off the UI thread, because docs/core-interface.md's threading contract
        // keeps mxq_store_archive_and_clear outside the main-actor exception the
        // active game's own commits run under. So the confirmation's answer is
        // not the same instant as the archive's, and this is the gap the guards
        // above are about.
        live.ArchiveAndClear(failure =>
        {
            // The state this answer is about has to still be the state, exactly
            // as the Apple frontend re-reads its own mode-switch inside this
            // same callback. Disposal is what invalidates it here: a window
            // closed while the archive was in flight would otherwise have this
            // open a pre-start page on a destination that has let go of
            // everything.
            if (token != _archiveAttempt)
            {
                return;
            }

            _saving = false;
            if (failure is null)
            {
                Release();
                OpenSetup(mode);
                return;
            }

            Alert = FlowAlert.ArchiveFailed;
            Publish();

            // The game is unchanged and still owes whatever it owed, so the
            // machine picks its search back up.
            live.Begin();
        });
    }

    // MARK: The pre-start page.

    /// <summary>One of **我先手**, **AI 先手**, **随机**.</summary>
    public void ChooseFirstMover(FirstMoverChoice choice)
    {
        if (Page != PlayPage.Setup || Draft.FirstMover == choice)
        {
            return;
        }

        Draft = Draft with { FirstMover = choice };
        Publish();
    }

    /// <summary>**AI 等级**: one of 快速, 标准, 深思.</summary>
    public void ChooseLevel(AiLevel level)
    {
        if (Page != PlayPage.Setup || Draft.Level == level)
        {
            return;
        }

        Draft = Draft with { Level = level };
        Publish();
    }

    /// <summary>
    /// **开始对局**.
    ///
    /// docs/engine-integration.md, "Accepted preparation ordering": prepare,
    /// resolve, create, search, each a gate on the next. A preparation failure
    /// creates nothing and resolves nothing; a **随机** choice is drawn only
    /// after preparation succeeds and is committed only by the create that
    /// follows, so a retry draws again; a persistence failure releases the
    /// prepared engine and creates nothing.
    /// </summary>
    public void StartGame()
    {
        if (Page != PlayPage.Setup || Creating)
        {
            return;
        }

        Creating = true;
        Alert = FlowAlert.None;
        int token = ++_attempt;
        Publish();

        if (SetupMode == PlayMode.FreePlay)
        {
            Create(PlayMode.FreePlay, humanSide: null);
            return;
        }

        // A fresh probe at every attempt. The prior value is never cached: the
        // retry that follows the insufficient-memory notice exists precisely to
        // see the memory the user just freed.
        MxqEngineBudget budget = _probe();

        // mxq_engine_prepare blocks — it allocates Hash and loads the network —
        // and the threading contract keeps it off the UI thread. Every task is
        // kept, not just the newest, because the same contract puts quiescence
        // on the caller and an abandoned attempt is still a call inside the
        // core. Finished ones are dropped here rather than from the completion,
        // so the list is only ever touched on this thread.
        _preparations.RemoveAll(finished => finished.IsCompleted);
        _preparations.Add(Task.Run(() =>
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
                    // The player left while this was in flight, or pressed 重试
                    // and a newer attempt owns the engine now. Either way this
                    // attempt creates nothing, and anything *it* prepared is
                    // released — but only when nothing newer is relying on it,
                    // because the engine is one engine and a stale completion
                    // must not pull it out from under the attempt that replaced
                    // it.
                    if (!Creating)
                    {
                        TeardownEngine();
                    }

                    return;
                }

                if (failure is not null)
                {
                    Creating = false;
                    Alert = Reports(failure);
                    Publish();
                    return;
                }

                // Everything from here is synchronous, so there is no second
                // window in which a completion could arrive late and commit.
                Create(PlayMode.HumanVersusAi, Draft.ResolveHumanSide());
            });
        }));
    }

    /// <summary>
    /// A preparation refusal, as the pre-start page presents it.
    ///
    /// By **code**, not by domain. Insufficient memory and a failed Hash
    /// allocation are one situation to the person in front of the screen —
    /// memory is not available right now — and the accepted notice says so once.
    /// Every other engine-domain failure reaches this from the same
    /// <c>mxq_engine_prepare</c> call: a missing or mismatched network, a
    /// variant that would not load, a faulted engine. Telling somebody to close
    /// other apps about a damaged installation is worse than telling them
    /// nothing, so those take the cause-free creation-failure notice instead.
    /// </summary>
    private static FlowAlert Reports(MxqException failure) =>
        failure.Status is Mxq.MXQ_ERR_ENGINE_INSUFFICIENT_MEMORY
            or Mxq.MXQ_ERR_ENGINE_HASH_ALLOCATION_FAILED
            ? FlowAlert.AiUnavailable
            : FlowAlert.GameNotStarted;

    private void Create(PlayMode mode, Side? humanSide)
    {
        try
        {
            GameSession game = mode == PlayMode.FreePlay
                ? _core.Create(
                    Mxq.MXQ_PLAY_MODE_FREE_PLAY,
                    Mxq.MXQ_COLOR_NONE,
                    Mxq.MXQ_AI_LEVEL_NONE,
                    Mxq.MXQ_FIRST_MOVER_NONE,
                    0)
                : _core.Create(
                    Mxq.MXQ_PLAY_MODE_HUMAN_VS_AI,
                    humanSide == Side.Black ? Mxq.MXQ_COLOR_BLACK : Mxq.MXQ_COLOR_RED,
                    Draft.Level.Code(),
                    Draft.FirstMover.Code(),
                    Draft.Level.MovetimeMs());

            Adopt(game);
            Creating = false;
            Page = PlayPage.Board;
            Publish();
            _session!.Begin();
        }
        catch (MxqException)
        {
            // The accepted 无法开始对局: a creation the store would not persist.
            // It cannot borrow 无法保存对局's wording, whose message promises
            // that the current game is unchanged, because there is no current
            // game to keep.
            Creating = false;
            Alert = FlowAlert.GameNotStarted;
            if (mode == PlayMode.HumanVersusAi)
            {
                // The engine was prepared for a game that does not exist.
                TeardownEngine();
            }

            Publish();
        }
    }

    // MARK: Leaving a page.

    /// <summary>
    /// The back control, which names the page it returns to — always the Play
    /// home.
    ///
    /// From a pre-start page that is leaving it, with everything leaving it
    /// means: the draft is discarded, an attempt in flight is invalidated, and
    /// no game is created. From the board it is only a navigation — the game
    /// stays active and the card on the home is the way back to it — unless it
    /// has been filed, in which case the record is in History and the board was
    /// showing nothing the home has any use for.
    /// </summary>
    public void LeaveTopPage()
    {
        switch (Page)
        {
            case PlayPage.Setup:
                LeaveSetup();
                break;

            case PlayPage.Board:
                if (_session is { IsFiled: true })
                {
                    Release();
                }

                Page = PlayPage.Home;
                Publish();
                break;
        }
    }

    private void LeaveSetup()
    {
        _attempt++;
        Creating = false;
        Alert = FlowAlert.None;
        Page = PlayPage.Home;
        Publish();
    }

    // MARK: Concluding a game.

    /// <summary>
    /// **开始新对局** on the play-control cluster, and **保存并开始新对局** on
    /// the result notice.
    ///
    /// docs/interaction-design.md, "Where the concluding actions go": it files
    /// the game and opens **that game's own mode's pre-start state**. It does
    /// not deal the next game — with an opponent to choose, the side and the
    /// level are chosen for each game rather than inherited from the last one.
    /// A claimed draw and an already-saved result were both filed before this
    /// was pressed, and neither is filed twice. A filing the store refuses
    /// resets nothing: the accepted 无法保存对局 retry presents on the session,
    /// and the game stays exactly as it stood.
    /// </summary>
    public void StartNewGame()
    {
        if (_session is not { } live || !live.FileIfNeeded())
        {
            return;
        }

        PlayMode mode = PlayVocabulary.Mode(live.Configuration.Mode);
        Release();
        OpenSetup(mode);
    }

    /// <summary>
    /// **完成** on the recorded notice: back to the Play home, with nothing
    /// filed a second time on the way.
    /// </summary>
    public void Finish()
    {
        if (_session is not { } live || !live.FileIfNeeded())
        {
            return;
        }

        Release();
        Page = PlayPage.Home;
        Publish();
    }

    // MARK: The game, and the engine behind it.

    private void OpenSetup(PlayMode mode)
    {
        _requested = null;
        SetupMode = mode;
        Draft = SetupDraft.FromDefaults(_preferences);
        Alert = FlowAlert.None;
        Creating = false;
        _attempt++;
        Page = PlayPage.Setup;
        Publish();
    }

    private void Adopt(GameSession game)
    {
        _session = new PlaySession(_core, game, _scheduler, _probe);
        _session.Changed += Publish;
    }

    /// <summary>
    /// Lets go of the game on the board and of the engine that was playing it.
    /// The order is the contract's: cancel, then release, because teardown
    /// refuses rather than stalls while a search is outstanding.
    /// </summary>
    private void Release()
    {
        if (_session is not { } live)
        {
            return;
        }

        bool wasHumanVersusAi = live.IsHumanVersusAi;
        live.Changed -= Publish;

        // Cancel before release, and cancel rather than abandon. A session's own
        // disposal only abandons what is in flight, because it was written for
        // the window closing — where the core's shutdown cancels everything a
        // moment later. Here the core lives on, and a search still outstanding
        // over a game nobody is playing is what makes the next preparation
        // answer MXQ_ERR_STATE_SEARCH_IN_PROGRESS.
        live.CancelSearch();
        live.Dispose();
        _session = null;
        if (wasHumanVersusAi)
        {
            TeardownEngine();
        }
    }

    /// <summary>
    /// Release the transposition table between games.
    ///
    /// It is not required for correctness — every human-versus-AI creation
    /// prepares again from a fresh probe, which is what
    /// docs/engine-integration.md means by "a later game in the same launch
    /// never silently reuses an earlier game's memory decision" — but a Hash
    /// bounded only by 4 GiB and the machine's memory is exactly the profile an
    /// operating system reclaims first, and nothing is playing.
    ///
    /// A refusal is absorbed. <c>mxq_engine_teardown</c> answers
    /// MXQ_ERR_STATE_SEARCH_IN_PROGRESS rather than stalling, and there is
    /// nothing to tell anybody about an optimisation that did not happen: the
    /// next preparation re-applies the plan either way, and the core's own
    /// shutdown releases it at quit.
    /// </summary>
    private void TeardownEngine()
    {
        try
        {
            if (_core.Engine.State == Mxq.MXQ_ENGINE_STATE_READY)
            {
                _core.TeardownEngine();
            }
        }
        catch (MxqException)
        {
        }
    }

    private void Publish() => Changed?.Invoke();

    /// <summary>
    /// Quiesce and release, in the order the shutdown promise requires: this
    /// object's own off-thread call is waited for, then the session's, before
    /// the core is shut down by whoever owns it.
    /// </summary>
    public void Dispose()
    {
        // Nothing this object started may still be inside the core when whoever
        // owns the core shuts it down. An archive answering after this decides
        // nothing, and every preparation still running is waited for — every
        // one, including an attempt the player walked out of.
        _archiveAttempt++;
        _saving = false;

        foreach (Task preparation in _preparations)
        {
            try
            {
                preparation.Wait();
            }
            catch (AggregateException)
            {
                // The preparation's own failure was already reported through the
                // scheduler, or will never be delivered because the window is
                // closing. Either way there is nobody left to tell.
            }
        }

        _preparations.Clear();
        if (_session is { } live)
        {
            live.Changed -= Publish;
            live.CancelSearch();
            live.Dispose();
            _session = null;
        }
    }
}
