// Feedback that is felt or heard, at the two moments the contract names.
//
// docs/interaction-design.md, "Motion and visual effects" and "Sound and
// haptics": feedback that reports an event fires when the event completes — a
// move sounds when the piece lands, not when it lifts — and feedback that
// answers a touch leads its animation. An illegal tap is a normal part of
// learning, so it takes the platform's lightest selection-weight feedback and
// never the warning pattern; on macOS the warning haptic does not exist at
// all, which satisfies that by construction. Haptics fire only where the
// hardware provides them — a Force Touch trackpad — and the system performer
// already honours the user's own trackpad setting.

import AppKit

struct Feedback {
    enum Event: Equatable {
        /// A disc arriving on its point — a move's or an Undo's.
        case landing
        /// The answer to a touch the game cannot act on: an illegal tap, or
        /// the acknowledgment beat.
        case acknowledgement
    }

    var perform: (Event) -> Void

    /// The hardware feedback, pattern chosen by what the event means:
    ///
    /// - `.alignment` for the landing, because Apple defines it for the moment
    ///   a dragged or moved object snaps into alignment — which is exactly a
    ///   disc settling onto a grid intersection. Performed at `.drawCompleted`
    ///   so the tap under the finger coincides with the drawn arrival.
    /// - `.generic` for the touch answer: the platform's unmarked, lightest
    ///   pattern, with none of `.levelChange`'s pressure semantics. Performed
    ///   `.now`, because the touch is what the player is waiting to feel
    ///   answered.
    static let live = Feedback { event in
        let performer = NSHapticFeedbackManager.defaultPerformer
        switch event {
        case .landing:
            // The sound seam. The landing is where a move's sound belongs —
            // the event completing, not the tap that asked for it — and the
            // sound pass adds its assets and playback here.
            performer.perform(.alignment, performanceTime: .drawCompleted)
        case .acknowledgement:
            performer.perform(.generic, performanceTime: .now)
        }
    }
}
