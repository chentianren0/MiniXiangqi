// A disc travelling across the board, and the arrival that ends it.
//
// Everything here was PlayMotion's, and it was lifted out when replay's steps
// began to travel: a replayed move and a played one are the same event drawn
// the same way, and a second copy of this would be a second thing to keep
// right. What lives here is what is true of a travelling disc wherever it
// travels — the transit the canvas draws, the disc fading at one end of it,
// the two wires the arrival comes in on, and the token that keeps a completion
// belonging to a finished transition from landing the one that replaced it.
//
// What deliberately does *not* live here is any rule about what may travel or
// what a travel means. Play holds a committing gate over this and mutates a
// game inside it; replay holds nothing, commits nothing, and lets a second
// step re-target the first. Those are decisions about a screen, not about a
// disc, and they stay with the screens that make them.

import SwiftUI

/// Runs an animation and reports its completion. The live one is SwiftUI's;
/// a test's holds the completion until the test fires it, so the gate can be
/// observed mid-transition without sleeping through one.
struct MotionAnimator {
    var perform: (Animation, () -> Void, @escaping () -> Void) -> Void

    func run(_ animation: Animation, body: () -> Void,
             completion: @escaping () -> Void) {
        perform(animation, body, completion)
    }

    static let live = MotionAnimator { animation, body, completion in
        withAnimation(animation, completionCriteria: .logicallyComplete, body) {
            MainActor.assumeIsolated(completion)
        }
    }
}

/// A transition as the board draws it: the visual move, the disc making it,
/// and the disc fading at one end — a capture giving way at the destination,
/// or a piece returning at the origin of a move being taken back.
struct Transit {
    enum Kind { case move, undo }

    var kind: Kind
    var move: Move
    var piece: Piece
    /// The piece fading while the mover travels, and where it fades.
    var fading: (piece: Piece, at: Square)?
}

@Observable
final class TransitMotion {

    /// What the board is drawing for the running transition.
    private(set) var transit: Transit?

    /// A second disc travelling in the same transition. One transition means
    /// one travel and one arrival, so a pair is drawn together rather than one
    /// after the other: taking back a decision cycle is one action, and the
    /// exchange rewinds in one gesture. Nothing else pairs, and replay never
    /// does.
    private(set) var companion: Transit?

    /// The fading disc's progress, 0 to 1 — scheduled against the mover's
    /// arrival for a capture, from its departure for a restoration.
    private(set) var fade: Double = 0

    /// Whether a transition is running. Raised at the departure, *before* the
    /// body that may yet abandon it, so a caller holding a gate over this
    /// holds it from the first instant.
    private(set) var isRunning = false

    /// Whether this transition draws a removal at all: a capture in full
    /// motion does, a restoration and everything under Reduce Motion do not.
    /// Resolved once, when the transition begins, and never read back off a
    /// policy afterwards — Reduce Motion can be switched *while* a transition
    /// runs, and an arrival that asked the live policy what the departure had
    /// scheduled would sit waiting for a removal nobody ever drew.
    private(set) var drawsRemoval = false

    /// The mover has reached its point. Announced once per transition, on
    /// whichever wire reports it first; what a landing *means* — what it
    /// sounds like, what it opens — belongs to the caller.
    var arrived: () -> Void = { }

    /// The transition is over: the arrival, plus a removal's tail where one
    /// was drawn. Never called for a transition that was abandoned or cut,
    /// because neither of those arrived anywhere.
    var ended: () -> Void = { }

    private let animator: MotionAnimator

    /// Ties a completion to the transition that scheduled it. A transition
    /// abandoned in its own body — a move the core refused, a ply the replay
    /// session would not answer for — still gets its completion called, and
    /// the token keeps that stale call from ending some later transition.
    private var generation = 0

    /// The landing arrives on two wires — the board's own animation reaching
    /// its target, and the transaction completion as its backstop — and each
    /// event counts once, whichever wire reports it first.
    private var travelReported = false
    private var fadeReported = false

    init(animator: MotionAnimator = .live) {
        self.animator = animator
    }

    // MARK: - Departure

    /// Runs one transition. The body makes whatever change the caller is
    /// making — a move committed, a ply walked — and answers with the transit
    /// to draw, or `nil` if nothing happened after all. `drawingRemoval` is
    /// the plan the arrival will be judged against, and it is settled here,
    /// before anything can arrive.
    func run(_ animation: Animation, drawingRemoval removal: Bool = false,
             body: () -> Transit?) {
        isRunning = true
        drawsRemoval = removal
        travelReported = false
        fadeReported = false
        generation += 1
        let token = generation
        animator.run(animation) { [self] in
            guard let started = body() else {
                abandon(token)
                return
            }
            transit = started
        } completion: { [self] in
            guard generation == token else { return }
            travelArrived()
        }
    }

    /// Raises the fading disc. Whether the transition waits for it was settled
    /// at the departure: a removal's tail holds the transition open past the
    /// arrival it answers, while a restoration finishes inside the travel and
    /// nothing waits for it. Does nothing where there is no disc to fade.
    func pair(with second: Transit) {
        guard isRunning, transit != nil else { return }
        companion = second
    }

    func raiseFade(_ animation: Animation) {
        guard isRunning, transit?.fading != nil || companion?.fading != nil else { return }
        let token = generation
        animator.run(animation) { [self] in
            fade = 1
        } completion: { [self] in
            guard drawsRemoval, generation == token else { return }
            fadeArrived()
        }
    }

    /// Abandons whatever is running and draws nothing — the presentational
    /// cut. Nothing arrived, so nothing lands and nothing sounds; the
    /// completions the abandoned transition still has parked answer to
    /// nothing, because the token has moved on.
    func cut() {
        generation += 1
        clear()
    }

    // MARK: - Arrivals

    /// The mover has reached its point. Reported by the board's animation on
    /// the frame it arrives, and by the transaction completion as a backstop;
    /// the first report is the landing, the second is nothing.
    func travelArrived() {
        guard isRunning, !travelReported else { return }
        travelReported = true
        arrived()
        // A removal outlives the arrival that caused it, and the transition
        // holds for that tail — when one is being drawn. Whether one is was
        // settled at the departure.
        guard !drawsRemoval || fadeReported else { return }
        end()
    }

    /// A removal has finished, 50 ms behind the arrival it answers. Both wires
    /// report it too; the transition ends on the later of the two events,
    /// wherever each was heard first.
    func fadeArrived() {
        guard isRunning, drawsRemoval, !fadeReported else { return }
        fadeReported = true
        if travelReported { end() }
    }

    // MARK: - Endings

    private func abandon(_ token: Int) {
        guard generation == token else { return }
        clear()
    }

    private func end() {
        clear()
        ended()
    }

    private func clear() {
        isRunning = false
        drawsRemoval = false
        transit = nil
        companion = nil
        fade = 0
    }
}
