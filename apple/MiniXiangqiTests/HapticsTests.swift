// The felt half's two decisions, and the audio session's one.
//
// What cannot be tested here is what any of it feels like or sounds like: a
// generator fired in a test process taps nothing, and the strength of a landing
// in the hand is settled on hardware by the owner's device pass, exactly as
// motion's exact durations are. What is testable is everything *around* that —
// which event asks for which generator, whether the switch is offered at all,
// and what the board's sounds are to the rest of the phone — and each of those
// is a clause of docs/interaction-design.md § Sound and haptics rather than a
// taste.

#if os(iOS)
import AVFoundation
import UIKit
#endif
import Testing
@testable import MiniXiangqi

@Suite("Haptics and the audio session")
@MainActor
struct HapticsTests {

    // MARK: - Whether the switch is offered

    /// "Haptics are available only where the hardware provides them; on a device
    /// without them the toggle is unavailable rather than silently ineffective."
    /// The rule is held apart from the hardware that feeds it so both answers can
    /// be asserted on one machine.
    @Test("A device that reports no haptics is not offered the switch")
    func noHardwareMeansNoSwitch() {
        #expect(Haptics.offered(whereHardwareReports: false) == false)
        #expect(Haptics.offered(whereHardwareReports: true))
    }

    /// The accepted macOS answer, which is the same shape as "the question could
    /// not be asked": the hardware question belongs to the trackpad, it can
    /// change while the app runs, and the system performer answers it per machine
    /// at the moment of the tap — so "a toggle the app greyed out by guessing at
    /// hardware would be a worse answer than the system's own."
    @Test("Where the hardware cannot be asked, the switch is offered")
    func anUnaskableQuestionOffersTheSwitch() {
        #expect(Haptics.offered(whereHardwareReports: nil))
    }

    /// Each platform asks the right source. macOS does not interrogate hardware
    /// at all; iOS does, and then follows what it is told rather than deciding by
    /// device family — which is the difference between detecting a Taptic Engine
    /// and assuming one from the shape of the device.
    @Test("Each platform's live answer comes from the source the contract names")
    func theLiveAnswerComesFromTheRightPlace() {
        #if os(macOS)
        #expect(Haptics.hardwareReportsHaptics == nil,
                "macOS leaves the hardware question to the system performer")
        #expect(Haptics.isOffered, "so 触感 is always offered there")
        #else
        let hardware = Haptics.hardwareReportsHaptics
        #expect(hardware != nil, "iOS asks the hardware rather than assuming")
        #expect(Haptics.isOffered == (hardware ?? false),
                "and the switch follows exactly what it was told")
        #endif
    }

    // MARK: - Which event asks for which feedback

    #if os(iOS)

    /// The whole mapping, and the whole of it is two rows. A landing is an
    /// impact; a touch the game could not act on is the platform's lightest
    /// selection tick.
    @Test("Every landing feels the same, and every touch answer the lightest")
    func theMappingIsTheAcceptedOne() {
        #expect(Feedback.Event.landing.feel == .impact)
        #expect(Feedback.Event.acknowledgement.feel == .selection)
    }

    /// "Every landing takes the alignment pattern, **whatever the landing
    /// meant**; the touch answers take the lightest pattern. A result changes
    /// what is heard and not what is felt." There is one landing event and it has
    /// one feel, which is that clause made structural: a capture, a check and a
    /// conclusion differ in `Feedback.Sound` and nowhere here.
    @Test("The felt half has one landing and does not know what a landing meant")
    func aLandingIsOneFeelWhateverItMeant() {
        #expect(Feedback.Event.allCases.count == 2,
                "a third event would need a decision in the feel table")
        #expect(Feedback.Event.allCases.filter { $0.feel == .impact } == [.landing])
        #expect(Feedback.Sound.allCases.count == 4,
                "the heard half is where a landing's meaning is carried")
    }

    /// "It uses the platform's lightest selection-weight feedback and **never the
    /// system warning pattern**. The warning pattern is reserved for genuine
    /// failures such as an action that could not be saved."
    ///
    /// Held by the type rather than by vigilance: `HapticFeel` has no
    /// notification case, so no event can reach `UINotificationFeedbackGenerator`
    /// without this enum growing a case first — and this assertion failing is
    /// what that would look like.
    @Test("There is no warning pattern to reach for")
    func theWarningPatternIsUnreachable() {
        #expect(HapticFeel.allCases == [.impact, .selection])
    }

    /// The landing's weight, which is the one number the device pass will judge.
    /// `.rigid` is a collision between objects with little give — a wooden disc
    /// meeting a wooden board — and is the nearest iOS has to the `.alignment`
    /// pattern macOS performs for the same event.
    @Test("A landing is a rigid impact rather than a heavy or a soft one")
    func theLandingIsRigid() {
        #expect(HapticFeel.impactStyle == .rigid)
    }

    #endif

    /// The performer is built where the sounds are and survives a device with
    /// nothing to drive: on hardware without an engine it holds no generators and
    /// every event is a no-op, so a stored `haptics.enabled` from a device that
    /// had one cannot make it misbehave. Nothing is asserted about what it feels
    /// like, because nothing in a test process can be.
    @Test("The performer builds and performs on any device, hardware or none")
    func thePerformerIsHarmlessWithoutHardware() {
        for offered in [true, false] {
            let performer = HapticPerformer(offered: offered)
            for event in Feedback.Event.allCases {
                performer.perform(event)
            }
        }
    }

    // MARK: - The silent switch

    #if os(iOS)

    /// The decision: the board's sounds are `ambient`, which the Ring/Silent
    /// switch and the lock screen silence. `playback` — the category that plays
    /// through silence — is what this is not, and the assertion says so directly
    /// rather than only by naming the one that was chosen.
    @Test("The board's sounds obey the silent switch")
    func theSoundsObeyTheSilentSwitch() {
        #expect(BoardAudioSession.category == .ambient)
        #expect(BoardAudioSession.category != .playback,
                "playing through a silenced phone is the behaviour being refused")
        #expect(BoardAudioSession.category != .soloAmbient,
                "and the default category would have stopped the player's own audio")
    }

    /// Configured by the thing that plays, before it can play: constructing the
    /// sounds is what puts the session on the accepted category, so a board that
    /// sounds at all sounds through it. The category is asserted off the live
    /// session rather than off the constant, so a `setCategory` the system
    /// refused would be visible here rather than at somebody's ear.
    @Test("Building the board's sounds is what sets the session")
    func buildingTheSoundsSetsTheSession() throws {
        try AVAudioSession.sharedInstance().setCategory(.playback)
        #expect(AVAudioSession.sharedInstance().category == .playback,
                "the premise: the session starts on something else")

        _ = BoardSounds()
        #expect(AVAudioSession.sharedInstance().category == BoardAudioSession.category)
    }

    #endif
}
