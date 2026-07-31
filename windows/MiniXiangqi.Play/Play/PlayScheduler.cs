// The thread the interface lives on, as an interface.
//
// The play screen's logic runs on one thread and mutates state that one thread
// reads. Two things arrive from elsewhere and have to be brought to it: the
// search callback, which the core delivers on its own engine thread, and the
// engine preparation, which blocks and therefore runs on a pool thread. Both
// come back through here.
//
// It is an interface rather than a DispatcherQueue because the window is not
// the only thing that drives a game. MiniXiangqi.Smoke plays a whole game
// against the AI through this same session logic, headlessly, over SSH on a
// machine nobody is logged into — which is the only place a Windows frontend's
// behaviour can be run at all until somebody opens an RDP session.

using MiniXiangqi.Core;

namespace MiniXiangqi.Play;

public interface IPlayScheduler : ISearchDispatcher
{
    /// <summary>
    /// Run <paramref name="work"/> after <paramref name="delay"/>, on the
    /// interface's own thread. Disposing the token cancels it.
    /// </summary>
    IDisposable After(TimeSpan delay, Action work);
}

/// <summary>
/// A scheduler that queues everything and runs it when it is pumped. The
/// headless harness's, and the reason the play screen's logic can be driven
/// without a window.
/// </summary>
public sealed class PumpScheduler : IPlayScheduler
{
    private readonly Lock _gate = new();
    private readonly Queue<Action> _ready = new();
    private readonly List<(DateTime Due, Timer Timer)> _timers = [];

    public void Post(Action work)
    {
        lock (_gate)
        {
            _ready.Enqueue(work);
        }
    }

    public IDisposable After(TimeSpan delay, Action work)
    {
        Timer timer = new(work);
        lock (_gate)
        {
            _timers.Add((DateTime.UtcNow + delay, timer));
        }

        return timer;
    }

    /// <summary>
    /// Run everything that is ready. Returns whether anything ran, so a caller
    /// can idle rather than spin.
    /// </summary>
    public bool Pump()
    {
        bool ran = false;
        while (true)
        {
            Action? work = null;
            lock (_gate)
            {
                DateTime now = DateTime.UtcNow;
                for (int index = _timers.Count - 1; index >= 0; index--)
                {
                    (DateTime due, Timer timer) = _timers[index];
                    if (timer.Cancelled)
                    {
                        _timers.RemoveAt(index);
                    }
                    else if (now >= due)
                    {
                        _timers.RemoveAt(index);
                        _ready.Enqueue(timer.Work);
                    }
                }

                if (_ready.Count > 0)
                {
                    work = _ready.Dequeue();
                }
            }

            if (work is null)
            {
                return ran;
            }

            work();
            ran = true;
        }
    }

    /// <summary>Pump until <paramref name="until"/> is true, or the deadline passes.</summary>
    public bool PumpUntil(Func<bool> until, TimeSpan timeout)
    {
        DateTime deadline = DateTime.UtcNow + timeout;
        while (DateTime.UtcNow < deadline)
        {
            if (until())
            {
                return true;
            }

            if (!Pump())
            {
                Thread.Sleep(5);
            }
        }

        return until();
    }

    private sealed class Timer(Action work) : IDisposable
    {
        internal Action Work { get; } = work;

        internal bool Cancelled { get; private set; }

        public void Dispose() => Cancelled = true;
    }
}
