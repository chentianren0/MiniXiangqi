// The assets carry their own level (Sounds/generate.py); nothing here adjusts
// volume. Priming is why this type exists: a player built at the landing has
// its file to open and buffers to allocate first, and the tock would arrive
// after the disc.

import AVFoundation

final class BoardSounds {
    private var players: [Feedback.Sound: AVAudioPlayer] = [:]

    /// A missing or unreadable sample is left out rather than raised: sound is
    /// never the only channel, so a board without its samples is quiet, not
    /// broken. The session is configured first because silencing and mixing are
    /// properties of the session, not of any player.
    init(bundle: Bundle = .main) {
        BoardAudioSession.configure()
        for sound in Feedback.Sound.allCases {
            guard let url = bundle.url(forResource: sound.resource, withExtension: "wav"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.prepareToPlay()
            players[sound] = player
        }
    }

    /// The sounds that were named and not found.
    var missing: [Feedback.Sound] {
        Feedback.Sound.allCases.filter { players[$0] == nil }
    }

    func duration(of sound: Feedback.Sound) -> TimeInterval? {
        players[sound]?.duration
    }

    /// Rewound first, so a sound still ringing from the previous landing
    /// restarts rather than being ignored. One player per sound is enough: a
    /// committing transition runs to completion, so two moves cannot overlap.
    func play(_ sound: Feedback.Sound) {
        guard let player = players[sound] else { return }
        player.currentTime = 0
        player.play()
    }
}
