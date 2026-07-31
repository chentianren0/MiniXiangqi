// The four samples, loaded once and kept ready to sound.
//
// Which voice a landing takes is `MiniXiangqi.Play`'s and is run headlessly;
// this is the half that makes a noise, and it is here for the same reason every
// other window-bound thing is — it needs an audio endpoint and a desktop
// session, and the machine this project verifies on has neither.
//
// **The playback API is winmm's `PlaySound`, over an image of the WAV already in
// memory.** Four candidates were real, and this one is chosen on latency and on
// what the samples actually are:
//
//   * `PlaySound` with `SND_MEMORY | SND_ASYNC` hands the driver a buffer that
//     is already 16-bit PCM mono at 44.1 kHz — the generator's own format — so
//     there is no file to open, no source to resolve and no decoder to build at
//     the landing. It is also exactly what `System.Media.SoundPlayer` does
//     underneath; taking it directly costs eleven lines of P/Invoke and saves a
//     `System.Windows.Extensions` package reference that drags `System.Drawing`
//     behind it into an app that draws with Win2D. Hand-written platform
//     P/Invokes are already this frontend's established shape — see
//     `MiniXiangqi.Core`'s `WindowsMemoryProbe` — and this is one.
//   * `Windows.Media.Playback.MediaPlayer` is the modern general answer and is
//     the wrong shape here: it builds a full media pipeline — source resolution,
//     a decoder, a playback session — per instance, for a 110-millisecond
//     uncompressed knock that needs none of it, and its first play is the one
//     that costs most and matters most. Four of them would be four pipelines
//     resident for the life of a board.
//   * `AudioGraph` is the genuinely low-latency route and is the right answer for
//     audio that has to overlap or be mixed. Nothing here overlaps: the contract
//     is **one sound per landing**, and a committing transition runs to
//     completion, so two landings cannot be in the air at once. Its machinery
//     would be paying for a capability the design deliberately does not have.
//   * `ElementSoundPlayer` is WinUI's own sound set for its own controls. It
//     plays the platform's sounds, not ours.
//
// **A second sound stops the first, and it is the AudioGraph paragraph above
// that says why this is acceptable rather than the Mac's own behaviour.**
// `PlaySound` allows one asynchronous sound per process and a new call replaces
// whatever is ringing, so this diverges from the Apple player in one respect and
// matches it in the other:
//
//   * **The same voice twice in a row matches.** `BoardSounds.swift` rewinds a
//     player before starting it, "so a sound that is still ringing from the
//     previous landing restarts rather than being ignored" — which is what
//     replacing it does here.
//   * **Two different voices differ.** The Mac holds four `AVAudioPlayer`s and
//     a check over a still-ringing capture would *mix*; here the capture stops.
//     That divergence is near-unreachable rather than tolerated: the contract is
//     one sound per landing, a committing transition runs to completion, and
//     input arriving during one is discarded rather than queued — so a second
//     landing cannot be committed while the first is still inside a 145 ms
//     sample except by the machine answering a move within it, which no search
//     does. It is named because it is real, not because it has been seen.
//
// The choice stands on that: an API whose only cost is a tail nothing can reach
// beats one that builds a mixer to preserve it.
//
// **`SND_NODEFAULT` is not optional.** Without it, a sample the driver would not
// play falls back to the *system default sound* — so a missing or malformed file
// would answer a move with Windows' own ding, which is both louder than anything
// this board is allowed to be and a noise the contract never asked for. With it,
// a sample that cannot play is silence, which is what a board with no samples is
// supposed to be.
//
// **Backgrounding needs no code here either, and for the Mac's reason.** An
// unpackaged Win32 desktop app has no platform suspension: Windows does not
// suspend it, there is no `audio` background capability to declare or decline,
// and losing focus is not a suspension — which is exactly what
// `apple/MiniXiangqi/Play/Suspension.swift` says about macOS, where "an
// unfocused window is still a running app". So a game still being played is
// still heard, a minimised window included, and the volume mixer is where
// somebody who wants it quieter goes: `PlaySound` renders through this process's
// own audio session, so the app appears there under its own name.

using System.Runtime.InteropServices;
using MiniXiangqi.Play;

namespace MiniXiangqi.App;

/// <summary>The heard half of the board, against a real audio endpoint.</summary>
internal sealed partial class BoardSoundPlayer
{
    /// <summary>Play asynchronously and return at once.</summary>
    private const uint SndAsync = 0x0001;

    /// <summary>
    /// A sample that will not play is silence rather than the system default
    /// sound.
    /// </summary>
    private const uint SndNoDefault = 0x0002;

    /// <summary>The pointer is an image of a WAV file in memory.</summary>
    private const uint SndMemory = 0x0004;

    /// <summary>
    /// The four samples, read once and held in the pinned object heap.
    ///
    /// **Pinned deliberately, and this is the whole reason `GC.AllocateArray` is
    /// here rather than `File.ReadAllBytes`.** `SND_ASYNC` returns before the
    /// sound has finished, and the buffer must stay valid and stay put until it
    /// has. A `fixed` block would pin only for its own duration, which ends the
    /// instant playback begins; a POH allocation never moves at all, so the
    /// pointer taken below is good for the life of the process — which is exactly
    /// as long as the app can ask for another landing.
    ///
    /// Read at construction, which is the play screen's, so that the first tock
    /// is no later than the second: a sample opened at the landing has its file
    /// to find first, and the disc would arrive before the knock.
    /// </summary>
    private readonly Dictionary<BoardSound, byte[]> _samples = [];

    internal BoardSoundPlayer()
    {
        foreach (BoardSound sound in BoardSounds.All)
        {
            try
            {
                byte[] file = File.ReadAllBytes(BoardSoundAssets.PathFor(sound));
                byte[] pinned = GC.AllocateArray<byte>(file.Length, pinned: true);
                file.CopyTo(pinned, 0);
                _samples[sound] = pinned;
            }
            catch (Exception failure) when (
                failure is IOException or UnauthorizedAccessException)
            {
                // A sample that is not there is left out rather than raised.
                // Sound is never the only way anything is conveyed, so a board
                // that cannot find its samples is a quiet board and not a broken
                // one — and BoardSoundAssets.Missing is what the harness reads,
                // so a file that fell out of the build is caught there rather
                // than by silence.
            }
        }
    }

    /// <summary>One landing, heard. Called only through the 声音 gate.</summary>
    internal unsafe void Play(BoardSound sound)
    {
        if (!_samples.TryGetValue(sound, out byte[]? sample))
        {
            return;
        }

        fixed (byte* image = sample)
        {
            // The `fixed` is how the pointer is taken, not how the buffer is
            // kept still: the array is already in the pinned object heap, which
            // is what makes this pointer good after the block ends and after this
            // call returns.
            PlaySound(image, IntPtr.Zero, SndMemory | SndAsync | SndNoDefault);
        }
    }

    /// <summary>
    /// <c>winmm.dll!PlaySoundW</c>. `[LibraryImport]` rather than `[DllImport]`
    /// for the reason windows/README.md gives about the hand-written platform
    /// P/Invokes: the generated stub is explicit about what crosses, and nothing
    /// here needs marshalling at all — a pointer, a handle and a flag word.
    ///
    /// The return is `int` rather than `bool` so that no marshalling of the
    /// result is requested either. It is not read: a refusal here is a sample
    /// the audio stack would not take, and the answer to that is the silence the
    /// caller already gets.
    /// </summary>
    [LibraryImport("winmm.dll", EntryPoint = "PlaySoundW")]
    private static unsafe partial int PlaySound(byte* sound, IntPtr module, uint flags);
}
