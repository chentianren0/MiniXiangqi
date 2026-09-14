// The felt half of the feedback: the hardware question, and the performer that
// answers each event on each platform.
//
// docs/interaction-design.md, "Sound and haptics". Three of its clauses govern
// everything in this file.
//
// **The set is two patterns, and it is not derived from the sound set.** "Every
// landing takes the alignment pattern, whatever the landing meant; the touch
// answers take the lightest pattern. A result changes what is heard and not what
// is felt." So a capture, a check and a conclusion are heard and are not felt,
// and there is nothing here for any of them: the sound already says what a
// landing meant, and a second channel repeating it would be the board saying one
// thing twice. That is a decision about meaning rather than a limit of any
// platform's hardware — iOS has the palette to tell a capture from a quiet move
// in the hand, and deliberately does not. What the device pass may find is that
// a take wants mass; changing it then is this file's `feel` table and nothing
// else.
//
// **Strength follows the meaning of the event, not its frequency.** "Tapping an
// illegal square is a normal part of learning how the pieces move rather than a
// failure, so it uses the platform's lightest selection-weight feedback and never
// the system warning pattern." On macOS the warning pattern does not exist at
// all, which satisfied that by construction. On iOS it does exist, and it is kept
// out by construction here too: `HapticFeel` has no notification case, so no
// event can reach `UINotificationFeedbackGenerator` without this type changing
// first. The warning pattern stays reserved for the genuine failures the contract
// names — an action that could not be saved — which fire no haptic on any
// platform today; giving them one would be a new feedback event that nobody has
// accepted and nobody has felt.
//
// **Availability is answered rather than guessed.** "Haptics are available only
// where the hardware provides them; on a device without them the toggle is
// unavailable rather than silently ineffective." The two platforms answer that
// question from different places and both answers are the contract's own — see
// `Haptics.offered(whereHardwareReports:)`.

#if os(macOS)
import AppKit
#else
import CoreHaptics
import UIKit
#endif

enum Haptics {

    // MARK: - Whether the switch is offered at all

    /// Whether the Settings destination offers 触感 on this device.
    ///
    /// The policy is below and takes the hardware's answer as an argument, so
    /// both of the contract's cases can be held to without owning one device
    /// that has a Taptic Engine and one that does not.
    static var isOffered: Bool { offered(whereHardwareReports: hardwareReportsHaptics) }

    /// What the hardware says, where the hardware is the thing to ask.
    ///
    /// **iOS answers with Core Haptics' own device capability.** Apple's guidance
    /// on preparing an app to play haptics is to read
    /// `CHHapticEngine.capabilitiesForHardware().supportsHaptics` before doing
    /// anything else, and it names iPad among the devices that do not support
    /// haptic feedback. It is the public answer to the question; the alternatives
    /// are a private key on `UIDevice` and a list of model identifiers, and a
    /// list of models is a guess that goes stale on the next device. A feedback
    /// generator on a device without the hardware is silently ineffective rather
    /// than an error, which is precisely the state the contract forbids the
    /// *switch* to be in, so the question has to be asked before the switch is
    /// drawn rather than discovered by nothing happening.
    ///
    /// **macOS answers `nil` — the question cannot be asked here, and that is the
    /// accepted answer rather than a gap.** The hardware question belongs to the
    /// trackpad rather than to the machine, a trackpad may be built in, attached,
    /// or neither, and that can change while the app is running.
    /// `NSHapticFeedbackManager`'s performer already honours each machine's own
    /// trackpad at the moment of the tap and does nothing where there is none, so
    /// a snapshot taken when Settings was drawn would be worse than the system's
    /// own continuous answer.
    static var hardwareReportsHaptics: Bool? {
        #if os(macOS)
        nil
        #else
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
        #endif
    }

    /// The presentation rule, apart from the hardware that feeds it.
    ///
    /// - A hardware answer of `false` hides the switch. **Hidden rather than
    ///   disabled**: this is not a state the device can leave, so a permanently
    ///   greyed switch would be a control the user can never reach beside a
    ///   sentence about hardware they cannot change — and the accepted screen
    ///   deliberately carries only two footers, because "a footer under every
    ///   group is a screen nobody reads". iOS's own Settings does the same thing
    ///   on a device without the engine: the haptic rows are not there. The
    ///   remaining group is 声音 alone, which the accepted layout survives
    ///   unchanged — it has no header to be left stranded, and the two switches
    ///   are "neither nested under nor conditioned on the other", so removing one
    ///   says nothing about the other.
    /// - An unanswerable question offers the switch, which is the accepted macOS
    ///   behaviour: "a toggle the app greyed out by guessing at hardware would be
    ///   a worse answer than the system's own."
    static func offered(whereHardwareReports hardware: Bool?) -> Bool {
        hardware ?? true
    }
}

#if os(iOS)

/// What an event feels like on iOS: the generator it reaches for, named apart
/// from UIKit so that "which event asks for which feedback" is one table.
///
/// **Two cases, and there is no third.** A notification case is the one this
/// enum could have had and does not: `UINotificationFeedbackGenerator` is the
/// warning pattern the contract reserves for genuine failures, and a type that
/// cannot name it is a stronger guarantee than a comment saying nobody should.
enum HapticFeel: Equatable, CaseIterable {
    /// `UIImpactFeedbackGenerator`. A disc meeting the board.
    case impact
    /// `UISelectionFeedbackGenerator`. The answer to a touch.
    case selection

    /// The impact's weight. `.rigid` is Apple's "collision between user interface
    /// elements that are rigid, exhibiting a small amount of compression or
    /// elasticity" — which is a wooden disc meeting a wooden board, and is the
    /// nearest thing iOS has to the `.alignment` pattern macOS uses for the same
    /// event, an object snapping into place on a grid. `.heavy` would be a
    /// different object and `.soft` a different material; the weight is not the
    /// place a capture gets told apart from a quiet move, which is the sound's
    /// job.
    ///
    /// Exact strength is settled on hardware, within the accepted bands, exactly
    /// as motion's exact durations are. This is the starting point the device
    /// pass judges, not a measured answer.
    static let impactStyle: UIImpactFeedbackGenerator.FeedbackStyle = .rigid
}

extension Feedback.Event {
    /// The whole mapping. Every landing feels the same, whatever it meant; every
    /// touch answer takes the lightest tick there is.
    ///
    /// `UISelectionFeedbackGenerator` for the touch answer is the contract's own
    /// word made literal — "the platform's lightest selection-weight feedback" —
    /// and it is the only iOS generator whose weight is that of a picker's
    /// detent. Apple's note on `selectionChanged()` asks that it not be used to
    /// *make or confirm* a selection, and neither of these events does: an
    /// illegal tap and the acknowledgment beat are answers to a touch that
    /// changed nothing, which is the opposite of a confirmation. Recorded as a
    /// tension rather than smoothed over: the alternative is a light impact,
    /// which would tell the learner their exploratory tap collided with
    /// something, and the contract is explicit that an illegal tap is not a
    /// failure.
    var feel: HapticFeel {
        switch self {
        case .landing: .impact
        case .acknowledgement: .selection
        }
    }
}

#endif

/// The hardware feedback itself, performed at the moment each event's own rule
/// names.
///
/// Built once, with the sounds, at the play screen's construction. On iOS that
/// matters for the same reason priming the samples does: `prepare()` is what
/// buys a generator its lowest latency, and a generator built at the landing
/// would tap after the disc had already stopped.
@MainActor
final class HapticPerformer {
    #if os(iOS)
    /// Nil where the device has no engine to drive. Held for the life of the
    /// screen rather than made per event, because a generator is only ever
    /// prepared while something holds it.
    private let impacts: UIImpactFeedbackGenerator?
    private let selections: UISelectionFeedbackGenerator?
    #endif

    /// - Parameter offered: whether haptics are available here at all. Taken as
    ///   an argument so the performer and the Settings row cannot disagree about
    ///   the same device, and defaulted to the one answer both of them read.
    init(offered: Bool = Haptics.isOffered) {
        #if os(iOS)
        guard offered else {
            impacts = nil
            selections = nil
            return
        }
        let impacts = UIImpactFeedbackGenerator(style: HapticFeel.impactStyle)
        let selections = UISelectionFeedbackGenerator()
        impacts.prepare()
        selections.prepare()
        self.impacts = impacts
        self.selections = selections
        #endif
    }

    /// - macOS: `.alignment` at `.drawCompleted` for the landing, so the tap
    ///   under the finger coincides with the drawn arrival, and `.generic` at
    ///   `.now` for the touch answer, because the touch is what the player is
    ///   waiting to feel answered. Unchanged from the day the felt half was macOS
    ///   only.
    /// - iOS: the generator `feel` names. Each is re-prepared immediately after
    ///   it fires — the Taptic Engine idles as soon as feedback is triggered, and
    ///   Apple's own instruction is to call `prepare()` again straight away where
    ///   more feedback is likely within seconds, which on a board mid-game it is.
    func perform(_ event: Feedback.Event) {
        #if os(macOS)
        let performer = NSHapticFeedbackManager.defaultPerformer
        switch event {
        case .landing:
            performer.perform(.alignment, performanceTime: .drawCompleted)
        case .acknowledgement:
            performer.perform(.generic, performanceTime: .now)
        }
        #else
        switch event.feel {
        case .impact:
            impacts?.impactOccurred()
            impacts?.prepare()
        case .selection:
            selections?.selectionChanged()
            selections?.prepare()
        }
        #endif
    }
}
