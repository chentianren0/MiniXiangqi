// Shared by play and replay. No rule about what may travel lives here: play
// holds a committing gate over this, while replay commits nothing and lets a
// second step re-target the first.

import SwiftUI

/// The live one is SwiftUI's; a test's holds the completion until the test
/// fires it, so a gate can be observed mid-transition without sleeping.
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

/// The visual move, the disc making it, and the disc fading at one end: a
/// capture giving way at the destination, or a piece returning at the origin
/// of a move being taken back.
struct Transit {
    enum Kind { case move, undo }

    var kind: Kind
    var move: Move
    /// The face the mover leaves with. In every game but Jieqi it is also the
    /// face it arrives with.
    var piece: Piece
    /// The piece fading while the mover travels, and where it fades.
    var fading: (piece: Piece, at: Square)?
    /// The face the mover **arrives** with, where the move turns it up; nil
    /// wherever a move reveals nothing. The identity comes up on the travelling
    /// disc rather than snapping on at the end.
    var revealed: Piece?

    init(kind: Kind, move: Move, piece: Piece,
         fading: (piece: Piece, at: Square)? = nil, revealed: Piece? = nil) {
        self.kind = kind
        self.move = move
        self.piece = piece
        self.fading = fading
        self.revealed = revealed
    }
}

@Observable
final class TransitMotion {

    private(set) var transit: Transit?

    /// Drawn together with `transit`, one travel and one arrival: taking back a
    /// decision cycle is one action. Replay never pairs.
    private(set) var companion: Transit?

    /// The fading disc's progress, 0 to 1 — scheduled against the mover's
    /// arrival for a capture, from its departure for a restoration.
    private(set) var fade: Double = 0

    /// How far the arriving face has come up, 0 to 1: a Jieqi reveal only.
    /// Drawn inside the transition like a removal, but not an event: nothing
    /// waits for it and no landing is reported when it finishes.
    private(set) var reveal: Double = 0

    /// Whether a transition is running. Raised at the departure, *before* the
    /// body that may yet abandon it, so a caller holding a gate over this
    /// holds it from the first instant.
    private(set) var isRunning = false

    /// Resolved once, at the departure, and never read back off a policy:
    /// Reduce Motion can be switched while a transition runs, and an arrival
    /// asking the live policy would wait for a removal nobody drew.
    private(set) var drawsRemoval = false

    /// Announced once per transition, on whichever wire reports it first; what
    /// a landing means belongs to the caller.
    var arrived: () -> Void = { }

    /// The arrival, plus a removal's tail where one was drawn. Never called for
    /// a transition that was abandoned or cut.
    var ended: () -> Void = { }

    private let animator: MotionAnimator

    /// Ties a completion to the transition that scheduled it. A transition
    /// abandoned in its own body still gets its completion called, and the
    /// token keeps that stale call from ending a later transition.
    private var generation = 0

    /// The landing arrives on two wires, the board's own animation reaching its
    /// target and the transaction completion as backstop; each event counts once.
    private var travelReported = false
    private var fadeReported = false

    init(animator: MotionAnimator = .live) {
        self.animator = animator
    }

    // MARK: - Departure

    /// The body answers with the transit to draw, or `nil` if nothing happened
    /// after all. `drawingRemoval` is the plan the arrival is judged against,
    /// settled before anything can arrive.
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

    func pair(with second: Transit) {
        guard isRunning, transit != nil else { return }
        companion = second
    }

    /// A removal's tail holds the transition open past the arrival; a
    /// restoration finishes inside the travel and nothing waits for it.
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

    /// Nothing waits for it: the identity coming up is part of the landing.
    /// Either disc counts: in a paired transition only the first ply may have
    /// turned a piece over.
    func raiseReveal(_ animation: Animation) {
        guard isRunning, transit?.revealed != nil || companion?.revealed != nil
        else { return }
        animator.run(animation) { [self] in
            reveal = 1
        } completion: { }
    }

    /// The presentational cut: nothing arrived, so nothing lands or sounds, and
    /// the abandoned transition's parked completions answer to nothing.
    func cut() {
        generation += 1
        clear()
    }

    // MARK: - Arrivals

    /// The first report is the landing; the second is nothing.
    func travelArrived() {
        guard isRunning, !travelReported else { return }
        travelReported = true
        arrived()
        // A removal outlives the arrival, and the transition holds for its tail.
        guard !drawsRemoval || fadeReported else { return }
        end()
    }

    /// Both wires report it too; the transition ends on the later of the two
    /// events.
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
        reveal = 0
    }
}
