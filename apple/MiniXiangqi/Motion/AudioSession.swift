// What the board's sounds are to the rest of the phone: the audio session, and
// the silent switch's answer.
//
// docs/interaction-design.md, "Sound and haptics": sound reinforces meaningful
// actions and game events and "must never be the only way information is
// conveyed". Apple's own description of the `ambient` category is that same
// sentence written by somebody else — "the category for an app in which sound
// playback is nonprimary — that is, your app also works with the sound turned
// off" — so the contract picks the category rather than this file inventing one.
//
// **The silent switch silences the board, and now does so on purpose.** No
// behaviour is being repaired here: the platform default, `soloAmbient`, obeyed
// the switch already, so what changes is that obedience stops being an inherited
// accident and becomes a decision this file can be held to — a later category
// change cannot quietly take it away. `ambient` is silenced by the Ring/Silent
// switch and by screen locking, and that is the decision: a person who has moved
// that switch has already said what they want from the room they are in, and an
// app that knocks anyway has overruled them to say something it also said on the
// board. Nothing is lost by obeying, because by contract every sound has a
// visible counterpart and none of them is the only channel for anything. The
// alternative category, `playback`, plays through silence and is for apps whose
// audio *is* the app — music, video, a podcast; a Xiangqi board is not one, and
// choosing it would be the app claiming a standing it does not have.
//
// **What does change in behaviour is the other app's audio**, and that is the
// whole of this file's practical effect — the mixing paragraph below.
//
// **Haptics are not affected, and that is the point of two switches.** The felt
// half is not audio and does not pass through this session at all, so a silenced
// phone still lands a move in the hand. The contract's two channels are
// independent — "sound off leaves a landing felt, and haptics off leaves it
// heard" — and the silent switch is one more thing that can turn one of them off
// without touching the other.
//
// **It mixes, and the default category would not have.** The system default,
// `soloAmbient`, interrupts every other app's audio as soon as the session
// activates: a learner playing through a lesson, a podcast or their own music
// would lose it the moment the play screen was built. A board that stops a
// podcast to make room for one tock has its priorities backwards, and `ambient`
// mixes by definition — the `mixWithOthers` option is not passed because it would
// be restating what the category already means.
//
// **Nothing is activated here, deliberately.** Apple's guidance is to set the
// category early and defer activation until playback begins, so that an app that
// never makes a sound never interrupts anything; `AVAudioPlayer` activates the
// session as it plays, and an ambient session's activation interrupts nobody
// whenever it happens. There is nothing to resume after an interruption either:
// every sample is a one-shot of a few hundred milliseconds, so an interrupted
// tock is a tock that already belonged to a landing the player has finished
// watching.
//
// **Backgrounding needs no code.** The app declares no `audio` background mode
// and wants none — there is no board on screen to sound — so an ambient session
// stopping when the app leaves the foreground is exactly the wanted behaviour,
// arrived at by not asking for the other one. The engine's own suspension is a
// separate matter and lives in `Play/Suspension.swift`.
//
// macOS has no `AVAudioSession` and no silent switch. Its sounds follow the
// system volume, as they did before this file existed.

#if os(iOS)
import AVFoundation
#endif

enum BoardAudioSession {
    #if os(iOS)
    /// The category the board's sounds play through, and the whole of the silent
    /// switch's answer: `ambient` obeys it.
    static let category: AVAudioSession.Category = .ambient
    #endif

    /// Sets the category, once, before the first sample can sound.
    ///
    /// Called from `BoardSounds`' construction: the session belongs to the one
    /// thing in the app that plays audio, and a launch that never reaches the
    /// board configures nothing. A failure is swallowed for the reason a missing
    /// sample is — sound is never the only way anything is conveyed, so a session
    /// the system declined to configure is a quiet board and not a broken one.
    static func configure() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(category)
        #endif
    }
}
