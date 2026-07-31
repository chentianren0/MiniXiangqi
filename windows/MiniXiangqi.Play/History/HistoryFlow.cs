// The History destination: the list of filed games, the step-through viewer over
// them, and the two interchange paths.
//
// It is PlayFlow's counterpart and is shaped like it for the same reason — a
// WinUI 3 process cannot be launched over SSH, so anything inside the window can
// be exercised on no machine this project owns. Which page is showing, what a row
// action does, which alert an import answers with and what a deletion asks first
// all live here, with no window attached, and MiniXiangqi.Smoke drives every one
// of them.
//
// docs/interaction-design.md § History library is the whole specification of what
// is below. The clauses this file is an implementation of, in the order they are
// met:
//
//   * **The order is the core's and the list never re-sorts it**: the two
//     sections are the pinned prefix of what the store returned and the rest of
//     it. Nothing here holds a comparator.
//   * **An empty History says so quietly**, and a library that cannot be read
//     says *that* instead, in the failure-screen family, rather than showing an
//     empty list it has no evidence for.
//   * **删除前确认** gates every delete entry point identically, because they are
//     the same operation and the confirmation is about the operation rather than
//     about the gesture.
//   * **A pin or unpin the store refuses is not an alert.** The two sections are
//     what report it: the row does not move.
//   * **A successful import says nothing.** The row appears at the head of the
//     unpinned group and carries a brief highlight that decays. **Everything else
//     an import can answer is an alert**, because every one of them is a thing
//     that did not happen.
//
// Threading follows docs/core-interface.md exactly, and the two halves are not
// the same. The list reads, the pin, the delete and `mxq_store_history_open` are
// inside the documented main-thread exception — the reads commit nothing, the
// mutations are one commit per user action, and the open is the one whose cost
// rises with the game's length and is named for measurement. **Import and export
// are outside it** and go to a pool thread, coming back through the scheduler,
// exactly as PlayFlow's archive does.

using MiniXiangqi.Core;
using MiniXiangqi.Core.Interop;

namespace MiniXiangqi.Play;

/// <summary>Which of the destination's two pages is showing.</summary>
public enum HistoryPageKind
{
    /// <summary>The list of filed games, or the empty state where there are none.</summary>
    List,

    /// <summary>One record's read-only step-through viewer.</summary>
    Viewer,
}

/// <summary>Which blocking answer the destination is waiting for, if any.</summary>
public enum HistoryAlert
{
    None,

    /// <summary>删除这盘棋？ — the 删除前确认 gate in front of a permanent deletion.</summary>
    ConfirmDelete,

    /// <summary>无法删除这盘棋 — the record is still there. 取消 and 重试.</summary>
    DeleteFailed,

    /// <summary>
    /// 这盘棋已经在历史里 — a success that deliberately does not meet the
    /// expectation a first import sets. 查看 opens the record it found, and 好.
    /// </summary>
    ImportDuplicate,

    /// <summary>这个文件和历史中的一盘棋冲突 — same game, different content. 好.</summary>
    ImportConflict,

    /// <summary>这个文件由更新版本的 Mini Xiangqi 创建. No word in it means corrupt. 好.</summary>
    ImportNewerVersion,

    /// <summary>无法读取这个对局文件 — every other refusal the archive domain has. 好.</summary>
    ImportUnreadable,

    /// <summary>
    /// 历史中有一盘损坏的棋 — the one import answer about the library rather than
    /// about the file, and the only one that may say 损坏. 好, and no retry: a
    /// retry would find the same damage.
    /// </summary>
    ImportDamagedRecord,

    /// <summary>无法保存导入的对局 — the file was fine. 取消 and 重试.</summary>
    ImportSaveFailed,
}

public sealed class HistoryFlow : IDisposable
{
    /// <summary>
    /// The accepted import bound, checked before a file is read so that an
    /// oversized one is declined without allocating for it. The bound itself is
    /// the core's, and the core is still what enforces it — this only stops the
    /// frontend reading a gigabyte into memory to be told so.
    /// </summary>
    public const long ImportSizeLimit = 1024 * 1024;

    /// <summary>
    /// How long the row a successful import added stays highlighted.
    ///
    /// The accepted answer to a valid import is the row itself, carrying "a brief
    /// highlight that decays" — so something has to put it away, and it is this
    /// object rather than the window, for the reason every other decision here is
    /// here: a window cannot be run on the machine this frontend is verified on.
    /// The 600 ms is the Apple frontend's, which is where the value was settled.
    /// </summary>
    public static readonly TimeSpan HighlightDuration = TimeSpan.FromMilliseconds(600);

    private readonly MiniXiangqiCore _core;
    private readonly IPlayScheduler _scheduler;
    private readonly IPreferenceStore _preferences;

    /// <summary>The library revision the loaded list was true at.</summary>
    private ulong _revision;

    /// <summary>Which record 删除这盘棋？ is about, and its retry after a refusal.</summary>
    private ulong? _deleting;

    /// <summary>
    /// The bytes 无法保存导入的对局's 重试 repeats, which are the file's rather
    /// than the file's path: the file was read inside the picker's grant and no
    /// reference to it is kept afterwards, which is the right posture for input
    /// the repository calls untrusted.
    /// </summary>
    private byte[]? _importRetry;

    /// <summary>
    /// Whether a store call this object started is still in flight. It is what
    /// stops a second import or export overlapping the first, and what disposal
    /// waits for.
    /// </summary>
    private Task? _transfer;

    /// <summary>The pending decay of the imported row's highlight.</summary>
    private IDisposable? _decay;

    private int _attempt;

    public HistoryFlow(
        MiniXiangqiCore core,
        IPlayScheduler scheduler,
        IPreferenceStore? preferences = null)
    {
        _core = core;
        _scheduler = scheduler;
        _preferences = preferences ?? new FilePreferenceStore();
    }

    /// <summary>Raised on the scheduler's thread whenever anything below changed.</summary>
    public event Action? Changed;

    public HistoryPageKind Page { get; private set; } = HistoryPageKind.List;

    /// <summary>
    /// The filed games, in the core's own accepted order: pinned first, newest
    /// within each group, <c>record_id</c> descending as the tie-break.
    /// </summary>
    public IReadOnlyList<RecordSummary> Records { get; private set; } = [];

    /// <summary>
    /// How many of <see cref="Records"/> are the pinned group. The two sections
    /// are that prefix and the rest; there is no second ordering rule here.
    /// </summary>
    public int PinnedCount { get; private set; }

    /// <summary>
    /// Why the library could not be read, where it could not be: the diagnostic
    /// the failure screen shows beneath 历史未能载入, which is the core's own
    /// English rather than copy and is never localized.
    ///
    /// A library that cannot be read says *that* — in the failure-screen family —
    /// rather than showing an empty list it has no evidence for, which is why
    /// this is not folded into an empty <see cref="Records"/>.
    ///
    /// **One damaged record therefore blanks the whole list, and that is the
    /// judgment rather than an accident.** `mxq_store_history_page` answers about
    /// a page and not about a row: a record whose blob no longer decodes fails
    /// the call, and the interface offers no way to ask for the rest of the page
    /// without it. A frontend could read the library one `mxq_store_history_get`
    /// at a time to find the bad one, but that would be re-deriving the list
    /// operation the core owns out of a call meant for a single record, and it
    /// would still have nothing useful to say about the row it found. So the
    /// screen says the library could not be read, which is exactly true, and the
    /// diagnostic beneath it carries the core's own account of why.
    /// </summary>
    public string? LoadFailure { get; private set; }

    /// <summary>
    /// Bumped by every published change. It is what lets a surface redraw only
    /// what changed: everything on both destinations publishes through one
    /// event, so a list of rows would otherwise be rebuilt because a search
    /// finished somewhere else.
    /// </summary>
    public int Revision { get; private set; }

    /// <summary>Whether the list has been read at least once.</summary>
    public bool Loaded { get; private set; }

    /// <summary>还没有历史对局, and it offers nothing else to do.</summary>
    public bool IsEmpty => Loaded && LoadFailure is null && Records.Count == 0;

    /// <summary>
    /// The row a successful import just added. The answer to a successful import
    /// *is* the row — the list scrolls it into view and it carries a brief
    /// highlight that decays — and an alert about something already on screen
    /// would be an alert that trains people to dismiss alerts.
    /// </summary>
    public ulong? Highlighted { get; private set; }

    /// <summary>The record 查看 opens on the duplicate answer.</summary>
    public ulong? DuplicateRecord { get; private set; }

    /// <summary>The open viewer, on the viewer page.</summary>
    public ReplayViewer? Viewer { get; private set; }

    public HistoryAlert Alert { get; private set; }

    /// <summary>Whether an import or an export is in flight.</summary>
    public bool Transferring { get; private set; }

    // MARK: The list.

    /// <summary>
    /// Read the library. Both halves of the two-call protocol are the core's —
    /// the count, then the pages — and the revision each answered at is what says
    /// they saw the same library.
    /// </summary>
    public void Load()
    {
        try
        {
            // Null is the read that never settled: the library committed
            // something between the count and the pages more often than the
            // bounded retry allows. A half-read list is not the library, and
            // publishing one as if it were would be the screen stating something
            // it does not know.
            if (_core.AllHistory() is not { } page)
            {
                Fail("the library changed while it was being read");
            }
            else
            {
                Records = page.Records;
                _revision = page.Revision;

                // The pinned group is a prefix of what the core returned, so
                // counting it is reading the answer rather than re-deriving it.
                int pinned = 0;
                while (pinned < Records.Count && Records[pinned].Pinned)
                {
                    pinned++;
                }

                PinnedCount = pinned;
                LoadFailure = null;
            }
        }
        catch (MxqException failure)
        {
            Fail(Diagnose(failure));
        }

        Loaded = true;
        Publish();
    }

    private void Fail(string diagnostic)
    {
        Records = [];
        PinnedCount = 0;
        LoadFailure = diagnostic;
    }

    /// <summary>
    /// A core refusal as the failure screen shows it: the status, its stable
    /// name, its domain and the core's own short English detail. It is diagnostic
    /// text rather than copy and is never localized.
    /// </summary>
    public static string Diagnose(MxqException failure) =>
        $"{failure.StatusName} ({failure.Status}), domain {failure.Domain}\n{failure.Detail}";

    /// <summary>
    /// Read the library again if anything committed to it since the last read.
    /// The MVP's accepted answer to library-change observation is return values
    /// plus this cheap staleness check, with no notification mechanism.
    /// </summary>
    public void LoadIfChanged()
    {
        if (!Loaded || LoadFailure is not null)
        {
            Load();
            return;
        }

        try
        {
            if (_core.HistoryCount().Revision != _revision)
            {
                Load();
            }
        }
        catch (MxqException)
        {
            Load();
        }
    }

    /// <summary>
    /// The pinned prefix of the list, which is the 已置顶 section. With nothing
    /// pinned there is one unheaded section and the list reads as a plain list of
    /// games.
    /// </summary>
    public IEnumerable<RecordSummary> Pinned => Records.Take(PinnedCount);

    /// <summary>The rest of it, which is the 其他对局 section.</summary>
    public IEnumerable<RecordSummary> Others => Records.Skip(PinnedCount);

    /// <summary>
    /// 置顶 / 取消置顶. **A refusal is not an alert**: it is the accepted
    /// non-blocking treatment for a reversible, low-stakes action, and the two
    /// sections are what report it — the row does not move.
    /// </summary>
    public void SetPinned(ulong recordId, bool pinned)
    {
        try
        {
            _core.SetHistoryPinned(recordId, pinned);
        }
        catch (MxqException)
        {
            // Deliberately silent, and deliberately still followed by a re-read:
            // the list has to show what the store holds either way, and what the
            // store holds after a refusal is the row where it was.
        }

        Load();
    }

    // MARK: Deleting.

    /// <summary>
    /// 删除 — from the row's context menu, its keyboard command, or a screen
    /// reader's own action. **Every entry point is gated identically**, because
    /// they are the same operation and 删除前确认 is about the operation rather
    /// than about the gesture; this is that one gate, and the preference is read
    /// at the moment of use.
    /// </summary>
    public void RequestDelete(ulong recordId)
    {
        // Not while an import or an export is inside the core. Both are off this
        // thread by contract, and a deletion committed underneath one would take
        // the record an export is encoding or the record an import is about to
        // compare against — the row is still there a moment later, which is the
        // right answer for a gesture made at the wrong moment.
        if (Alert != HistoryAlert.None || Transferring)
        {
            return;
        }

        _deleting = recordId;
        if (Preferences.ConfirmsDeletion(_preferences))
        {
            Alert = HistoryAlert.ConfirmDelete;
            Publish();
            return;
        }

        Delete();
    }

    /// <summary>删除 on the confirmation, and the 重试 that repeats it.</summary>
    public void ConfirmDelete()
    {
        Alert = HistoryAlert.None;
        Delete();
    }

    private void Delete()
    {
        if (_deleting is not { } recordId)
        {
            return;
        }

        try
        {
            _core.DeleteHistoryRecord(recordId);
            _deleting = null;

            // A viewer standing on the record that was just deleted is a viewer
            // of nothing. Leaving it open would leave a page whose every fact
            // came from a row the library no longer has.
            if (Viewer?.Record.RecordId == recordId)
            {
                CloseViewer();
            }
        }
        catch (MxqException)
        {
            // 无法删除这盘棋: the record remains in the list, and the app presents
            // the same "could not do it, nothing changed, try again" alert the
            // rest of it uses. The record is kept so 重试 repeats the same
            // deletion rather than something near it.
            Alert = HistoryAlert.DeleteFailed;
        }

        Load();
    }

    // MARK: The viewer.

    /// <summary>
    /// Open a filed game's read-only step-through viewer, from its initial
    /// position.
    /// </summary>
    public void Open(ulong recordId)
    {
        if (Alert != HistoryAlert.None)
        {
            return;
        }

        try
        {
            RecordSummary record = _core.HistoryRecord(recordId);
            GameSession replay = _core.OpenHistoryRecord(recordId);
            Viewer?.Dispose();
            Viewer = new ReplayViewer(record, replay);
            Page = HistoryPageKind.Viewer;
            Highlighted = null;
        }
        catch (MxqException failure)
        {
            // A record that will not open is the library failing to be read, and
            // that is what the failure-screen family is for. It is deliberately
            // not an alert: there is no action to offer and nothing changed.
            LoadFailure = Diagnose(failure);
        }

        Publish();
    }

    /// <summary>The back control, which returns to the list.</summary>
    public void CloseViewer()
    {
        if (Page != HistoryPageKind.Viewer)
        {
            return;
        }

        Viewer?.Dispose();
        Viewer = null;
        Page = HistoryPageKind.List;

        // The list may have moved on while the viewer was open — a game finished
        // on the Play destination is a new row — so it is re-read rather than
        // assumed.
        LoadIfChanged();
        Publish();
    }

    /// <summary>One transport step. Publishing is this object's, not the viewer's.</summary>
    public void Step(Action<ReplayViewer> step)
    {
        if (Viewer is not { } viewer)
        {
            return;
        }

        step(viewer);
        Publish();
    }

    // MARK: Import.

    /// <summary>
    /// 导入… — one game file, opened from wherever the picker granted access to
    /// it.
    ///
    /// The size is checked before the bytes are read, so a file over the accepted
    /// 1 MiB bound is declined without allocating for it. The bytes are read here
    /// and no path, handle or bookmark is kept afterwards, which is the posture
    /// this repository's rules ask of an untrusted input.
    /// </summary>
    public void ImportFile(string path)
    {
        if (Transferring || Alert != HistoryAlert.None)
        {
            return;
        }

        byte[] bytes;
        try
        {
            FileInfo file = new(path);
            if (!file.Exists || file.Length > ImportSizeLimit)
            {
                Alert = HistoryAlert.ImportUnreadable;
                Publish();
                return;
            }

            bytes = File.ReadAllBytes(path);
        }
        catch (Exception failure) when (
            failure is IOException or UnauthorizedAccessException or NotSupportedException
                or ArgumentException)
        {
            // A file the app could not read at all is 无法读取这个对局文件 too.
            // The reader has one question — can this file be imported — and the
            // difference between a damaged archive and a file the filesystem
            // would not hand over is not an answer they can act on differently.
            Alert = HistoryAlert.ImportUnreadable;
            Publish();
            return;
        }

        Import(bytes);
    }

    /// <summary>重试 on 无法保存导入的对局, over the same bytes.</summary>
    public void RetryImport()
    {
        Alert = HistoryAlert.None;
        if (_importRetry is { } bytes)
        {
            Import(bytes);
        }
        else
        {
            Publish();
        }
    }

    private void Import(byte[] bytes)
    {
        Transferring = true;
        Alert = HistoryAlert.None;
        Highlighted = null;
        DuplicateRecord = null;
        int token = ++_attempt;
        Publish();

        // Off the UI thread: docs/core-interface.md keeps import outside the
        // exception the active game's own commits run under, and validation
        // replays every ply of the file through the rules facade.
        Run(() =>
        {
            ImportResult? created = null;
            MxqException? refusal = null;
            try
            {
                created = _core.ImportGame(bytes);
            }
            catch (MxqException caught)
            {
                refusal = caught;
            }

            _scheduler.Post(() =>
            {
                if (token != _attempt)
                {
                    return;
                }

                Transferring = false;
                if (created is { } imported)
                {
                    _importRetry = null;

                    // A duplicate is a success rather than an error — the core
                    // returned the record already holding this identity and these
                    // bytes — and it is the one success that still speaks, because
                    // it deliberately does not meet the expectation a first import
                    // sets.
                    if (imported.Outcome == Mxq.MXQ_IMPORT_EXISTING)
                    {
                        DuplicateRecord = imported.RecordId;
                        Alert = HistoryAlert.ImportDuplicate;
                    }
                    else
                    {
                        Highlighted = imported.RecordId;

                        // The light decays on its own. Nothing here dismisses
                        // anything the reader has to read: the row stays, and
                        // what goes away is the colour that pointed at it.
                        _decay?.Dispose();
                        _decay = _scheduler.After(HighlightDuration, ClearHighlight);
                    }
                }
                else if (refusal is not null)
                {
                    Alert = Answers(refusal);

                    // Only the save failure has a retry, so only it keeps the
                    // bytes. Every other refusal would find the same answer.
                    _importRetry = Alert == HistoryAlert.ImportSaveFailed ? bytes : null;
                }

                // Nothing was written on any refusal, so there is nothing to read
                // back — but the list is re-read either way, because it is what
                // reports a success and because a re-read of an unchanged library
                // is two cheap queries.
                Load();
            });
        });
    }

    /// <summary>
    /// Which answer an import refusal is, **by exact status inside the classes
    /// the core's own taxonomy distinguishes**.
    ///
    /// Three statuses are named and everything else falls to one of two families:
    ///
    ///   * <c>MXQ_ERR_STORE_IDENTITY_CONFLICT</c> — the same game as one in
    ///     History with different content. The comparison succeeded and
    ///     disagreed.
    ///   * <c>MXQ_ERR_ARCHIVE_UNSUPPORTED_VERSION</c> — the one message the data
    ///     contract requires to be distinct, and no word in it means corrupt.
    ///   * <c>MXQ_ERR_STORE_CORRUPT</c> — the record already under this file's
    ///     identity no longer decodes or no longer matches its recorded hash, so
    ///     the comparison an import has to make **cannot be made**. That is a
    ///     different thing from a conflict and from a save that failed: nothing
    ///     was being saved yet, and a retry would find the same damage.
    ///   * any other **archive-domain** status — a wrong file, a damaged one, an
    ///     oversized one — is 无法读取这个对局文件. The taxonomy deliberately does
    ///     not tell a file that is not ours from a file that is broken; both are
    ///     <c>MXQ_ERR_ARCHIVE_MALFORMED</c>, and telling them apart would mean
    ///     reading a diagnostic string reserved for logs.
    ///   * everything else — the store domain's I/O, busy and full, and any
    ///     status this build does not know — is 无法保存导入的对局, whose message
    ///     says the file was fine. That default arm is what
    ///     docs/core-interface.md requires of a frontend meeting an unknown code
    ///     inside a known domain.
    /// </summary>
    /// <remarks>
    /// It takes the status and its domain rather than the exception because two
    /// of the seven answers are reachable through no seam this repository is
    /// willing to build — a damaged stored record and a store that will not write
    /// — and a pure function of the two numbers is something the headless harness
    /// can state the whole mapping about. The five that *are* reachable are
    /// driven through the core besides.
    /// </remarks>
    public static HistoryAlert AnswerFor(int status, int domain) => status switch
    {
        Mxq.MXQ_ERR_STORE_IDENTITY_CONFLICT => HistoryAlert.ImportConflict,
        Mxq.MXQ_ERR_ARCHIVE_UNSUPPORTED_VERSION => HistoryAlert.ImportNewerVersion,
        Mxq.MXQ_ERR_STORE_CORRUPT => HistoryAlert.ImportDamagedRecord,
        _ => domain == Mxq.MXQ_DOMAIN_ARCHIVE
            ? HistoryAlert.ImportUnreadable
            : HistoryAlert.ImportSaveFailed,
    };

    private static HistoryAlert Answers(MxqException refusal) =>
        AnswerFor(refusal.Status, refusal.Domain);

    /// <summary>查看 on the duplicate answer: the record it found.</summary>
    public void ViewDuplicate()
    {
        ulong? record = DuplicateRecord;
        Alert = HistoryAlert.None;
        DuplicateRecord = null;
        if (record is { } found)
        {
            Open(found);
        }
        else
        {
            Publish();
        }
    }

    // MARK: Export.

    /// <summary>
    /// 共享 — one History record written out as one game file.
    ///
    /// The bytes are `mxq_store_export`'s, which is the store's own canonical
    /// document with a fresh export event stamped into it, and the name the
    /// window offers is <see cref="HistoryText.SuggestedFileName"/>'s.
    /// </summary>
    public void ExportTo(ulong recordId, string path)
    {
        if (Transferring)
        {
            return;
        }

        Transferring = true;
        int token = ++_attempt;
        Publish();

        Run(() =>
        {
            bool refused = false;
            try
            {
                File.WriteAllBytes(path, _core.ExportRecord(recordId));
            }
            catch (Exception caught) when (
                caught is MxqException or IOException or UnauthorizedAccessException)
            {
                // The store would not encode it, or the place the picker named
                // would not take it. Which of the two is a difference the reader
                // cannot act on differently, and neither is an alert — see below.
                refused = true;

                // **The picker creates the file before this call gets it**, so
                // every failure here leaves a `.mxq` behind that is empty or
                // half-written. A file of that name is a file somebody will try
                // to import, or send to somebody who will, and it can only refuse
                // — so what did not get written does not stay on disk. Failing to
                // remove it is not a second result: the export already failed.
                try
                {
                    File.Delete(path);
                }
                catch (Exception sweeping) when (
                    sweeping is IOException or UnauthorizedAccessException)
                {
                }
            }

            _scheduler.Post(() =>
            {
                if (token != _attempt)
                {
                    return;
                }

                Transferring = false;
                ExportRefused = refused;
                Publish();
            });
        });
    }

    /// <summary>
    /// Whether the last export did not produce a file.
    ///
    /// **It is not an alert, and that is a Windows judgment stated in the pull
    /// request rather than a clause borrowed from elsewhere.** The accepted flow
    /// hands a file to the platform's own sharing and has no failure presentation
    /// of its own, because on Apple platforms the share sheet owns everything
    /// after the file exists. Windows' equivalent is a Save As, and its own
    /// dialog is what reports a place it could not write to; a second alert
    /// behind it would be the app repeating the system.
    ///
    /// **Nothing in the window reads this yet**, which is the honest state of it:
    /// the case it reports is one the save dialog has usually already refused, so
    /// what would be shown is a second refusal — but a `mxq_store_export` that
    /// failed over a path the dialog accepted would then be silent. It is named
    /// in windows/README.md's known list rather than answered here, because
    /// answering it means deciding a presentation the accepted flow does not
    /// have. What the failure path does do is leave no file behind.
    /// </summary>
    public bool ExportRefused { get; private set; }

    // MARK: Alerts.

    /// <summary>取消 and 好: the way out of every alert this destination has.</summary>
    public void DismissAlert()
    {
        if (Alert is HistoryAlert.ConfirmDelete or HistoryAlert.DeleteFailed)
        {
            _deleting = null;
        }

        if (Alert == HistoryAlert.ImportSaveFailed)
        {
            _importRetry = null;
        }

        DuplicateRecord = null;
        Alert = HistoryAlert.None;
        Publish();
    }

    /// <summary>The row highlight decays; this is what puts it away.</summary>
    public void ClearHighlight()
    {
        if (Highlighted is null)
        {
            return;
        }

        Highlighted = null;
        Publish();
    }

    private void Run(Action work)
    {
        // One transfer at a time, and the previous one is kept rather than
        // dropped: the shutdown promise puts quiescence on the caller, and a task
        // nobody holds is a call that can still be inside the core when the core
        // is shut down.
        _transfer = Task.Run(work);
    }

    private void Publish()
    {
        Revision++;
        Changed?.Invoke();
    }

    /// <summary>
    /// Quiesce and release. Whatever this object started is waited for before
    /// whoever owns the core shuts it down, and an answer posted afterwards
    /// decides nothing.
    /// </summary>
    public void Dispose()
    {
        _attempt++;
        _decay?.Dispose();
        _decay = null;
        try
        {
            _transfer?.Wait();
        }
        catch (AggregateException)
        {
            // The transfer's own failure was already reported through the
            // scheduler, or will never be delivered because the window is
            // closing. Either way there is nobody left to tell.
        }

        _transfer = null;
        Viewer?.Dispose();
        Viewer = null;
    }
}
