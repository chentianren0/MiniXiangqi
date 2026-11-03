// `ambient`, because sound is never the only channel: the board obeys the
// silent switch and screen lock, and it mixes with other apps' audio where the
// default `soloAmbient` would stop a podcast the moment the play screen was
// built. `mixWithOthers` is not passed; the category already means it. Haptics
// do not pass through the session, so a silenced phone still lands a move in
// the hand.
//
// Nothing is activated here: `AVAudioPlayer` activates the session as it plays,
// so an app that never sounds never interrupts anything. No interruption
// handling, since every sample is a one-shot of a few hundred milliseconds, and
// no `audio` background mode, since with no board on screen there is nothing
// to sound.
//
// macOS has no `AVAudioSession` and no silent switch; its sounds follow the
// system volume.

#if os(iOS)
import AVFoundation
#endif

enum BoardAudioSession {
    #if os(iOS)
    static let category: AVAudioSession.Category = .ambient
    #endif

    /// Called from `BoardSounds`' init, so a launch that never reaches the board
    /// configures nothing. A failure is swallowed: a session the system declined
    /// to configure is a quiet board, not a broken one.
    static func configure() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(category)
        #endif
    }
}
