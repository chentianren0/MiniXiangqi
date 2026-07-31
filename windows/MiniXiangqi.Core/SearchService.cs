// The search facade's callback half, and the one place this frontend crosses
// back over the boundary from a thread the runtime did not create.
//
// docs/core-interface.md, "Threading contract": the completion callback runs on
// the core's engine thread, always — never the calling thread and never a
// platform queue. It must copy and return, it must not block, and its whole job
// is to hand the result to the frontend's dispatcher. So the callback here does
// exactly two things: it copies the result struct into storage that was
// allocated before the search started, and it posts one delegate that was
// created before the search started. Building the managed answer — which means
// allocating three strings out of fixed-capacity char arrays — happens on the
// UI thread afterwards, because it is work, and work is what a callback on the
// engine thread must not do.
//
// The callback itself is an [UnmanagedCallersOnly] static, so there is no
// delegate for the core to hold and nothing to keep alive; what is pinned is
// the state it is handed, through a GCHandle whose IntPtr rides across as
// user_data. That handle is freed on the UI thread after delivery and never
// before, because a cancelled search's callback still fires and freeing early
// is how it would find nothing there.

using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using MiniXiangqi.Core.Interop;

namespace MiniXiangqi.Core;

/// <summary>
/// Where a search's answer is delivered. The core hands it over on the engine
/// thread; this is what carries it to the thread the interface lives on.
/// </summary>
public interface ISearchDispatcher
{
    /// <summary>
    /// Run <paramref name="work"/> on the interface's own thread. Called from
    /// the engine thread, so it must not block and must not run the work
    /// inline.
    /// </summary>
    void Post(Action work);
}

/// <summary>
/// One outstanding search at a time. This app has one window, one active game,
/// and one side for the machine to play, so a second is a bug rather than a
/// case.
/// </summary>
public sealed unsafe class SearchService : IDisposable
{
    private readonly MiniXiangqiCore _core;
    private readonly ISearchDispatcher _dispatcher;
    private Pending? _pending;

    public SearchService(MiniXiangqiCore core, ISearchDispatcher dispatcher)
    {
        _core = core;
        _dispatcher = dispatcher;
    }

    /// <summary>The ticket of the search in flight, if there is one.</summary>
    public ulong? Ticket => _pending?.Ticket;

    /// <summary>
    /// Start a search over <paramref name="session"/>.
    /// <paramref name="movetimeMs"/> is a cross-check rather than an input: the
    /// session already froze the only legal value, and the two are required to
    /// agree so that a level changed after creation cannot silently produce a
    /// move thought for a time the archive does not record.
    ///
    /// <paramref name="answered"/> runs on the dispatcher's thread.
    /// </summary>
    public ulong Start(GameSession session, uint movetimeMs, Action<SearchAnswer> answered)
    {
        Cancel();

        Pending pending = null!;
        pending = new Pending(_dispatcher, answer =>
        {
            if (ReferenceEquals(_pending, pending))
            {
                _pending = null;
            }

            answered(answer);
        });

        try
        {
            MxqSearchRequest request = default;
            request.struct_size = (uint)sizeof(MxqSearchRequest);
            request.movetime_ms = movetimeMs;

            ulong ticket;
            MxqError err = MxqCall.Error();
            MxqCall.Check(
                Mxq.mxq_search_start(
                    _core.Handle,
                    session.Handle,
                    &request,
                    &OnSearchComplete,
                    (void*)pending.Cookie,
                    &ticket,
                    &err),
                in err,
                nameof(Mxq.mxq_search_start));

            pending.Ticket = ticket;
            _pending = pending;
            return ticket;
        }
        catch
        {
            // The core never took the cookie, so nothing can call back into it
            // and the handle is this thread's to release.
            pending.Release();
            throw;
        }
    }

    /// <summary>
    /// Stop the machine thinking, because what it is thinking about is about to
    /// stop being true — an Undo, a claim, a resignation. Cancellation is a
    /// correctness requirement and not only a promptness one: a cancellation
    /// that follows no mutation leaves the position revision matching, so the
    /// cancelled rung is the only one that would reject the late result.
    ///
    /// The cancelled search's callback still fires. It answers to nothing,
    /// because the state it carries is marked abandoned here.
    /// </summary>
    public void Cancel()
    {
        if (_pending is not { } pending)
        {
            return;
        }

        _pending = null;
        pending.Abandon();

        // Cancelling an unknown or already-finished ticket is MXQ_OK, so the
        // race between a result arriving and this asking has no losing side.
        MxqError err = MxqCall.Error();
        MxqCall.Check(
            Mxq.mxq_search_cancel(_core.Handle, pending.Ticket, &err),
            in err,
            nameof(Mxq.mxq_search_cancel));
    }

    /// <summary>
    /// Abandon whatever is in flight without asking the core anything, for the
    /// teardown path where the core is being shut down anyway — shutdown
    /// cancels all work and joins the engine thread itself.
    /// </summary>
    public void Dispose() => _pending?.Abandon();

    // The callback. Copy and return, and nothing else: no core call, no
    // blocking, no allocation the engine thread would have to wait on.
    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    private static void OnSearchComplete(MxqSearchResult* result, void* userData)
    {
        Pending pending = (Pending)GCHandle.FromIntPtr((nint)userData).Target!;
        pending.Result = *result;
        pending.HandOff();
    }

    /// <summary>
    /// One search's state, pinned for as long as the core may call back into
    /// it. Everything the callback touches exists before the search starts.
    /// </summary>
    private sealed class Pending
    {
        private readonly ISearchDispatcher _dispatcher;
        private readonly Action<SearchAnswer> _answered;
        private readonly Action _deliver;
        private GCHandle _handle;
        private volatile bool _abandoned;

        internal MxqSearchResult Result;

        internal Pending(ISearchDispatcher dispatcher, Action<SearchAnswer> answered)
        {
            _dispatcher = dispatcher;
            _answered = answered;
            _deliver = Deliver;
            _handle = GCHandle.Alloc(this);
        }

        internal ulong Ticket { get; set; }

        internal nint Cookie => GCHandle.ToIntPtr(_handle);

        /// <summary>
        /// Called on the engine thread, after the copy. Posting is the whole of
        /// it.
        /// </summary>
        internal void HandOff() => _dispatcher.Post(_deliver);

        /// <summary>This search is superseded; its answer decides nothing.</summary>
        internal void Abandon() => _abandoned = true;

        internal void Release()
        {
            if (_handle.IsAllocated)
            {
                _handle.Free();
            }
        }

        private void Deliver()
        {
            MxqSearchResult result = Result;
            bool abandoned = _abandoned;
            Release();
            if (abandoned)
            {
                return;
            }

            _answered(new SearchAnswer(
                result.outcome,
                Utf8.Read(result.move.text),
                result.ticket,
                Utf8.Read(result.game_id),
                result.position_revision,
                result.status,
                result.depth,
                result.nodes,
                result.score_cp,
                result.elapsed_ms,
                Utf8.Read(result.profile_id)));
        }
    }
}
