// The transient save-failure capsule.
//
// docs/interaction-design.md, "Move input and feedback": a failed save on the
// player's own move is reported by brief feedback at the turn status and by
// nothing else — nothing modal, nothing on the board, because the board did not
// change.
//
// It lives here rather than inside one screen because two boards raise it now
// and they raise the same thing: the accepted words, the same four seconds, the
// same announcement, the same identifier. What differs between them is only
// *when* it is raised, and that stays with each board — the local board raises
// it on a ply whose commit was refused, and the nearby board on a ply of the
// player's own the library would not keep.

import SwiftUI

struct SaveFailureCapsule: View {
    /// Put the capsule away. Called by its own clock, so the screen holding the
    /// flag is the one that lowers it.
    var withdraw: () -> Void

    @Environment(\.motionPolicy) private var policy

    var body: some View {
        Label("status.saveFailed", systemImage: "exclamationmark.triangle")
            .font(.callout)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .accessibilityIdentifier("save-failure")
            // A warning symbol in place of the warning haptic a Mac does not
            // have, and a screen reader hears it arrive rather than having to
            // catch it.
            .onAppear {
                AccessibilityNotification
                    .Announcement(String(localized: "status.saveFailed"))
                    .post()
            }
            .task {
                // Transient by its own clock: long enough to read twice, gone
                // without being asked. A second refusal re-raises it — the
                // flag passes through false as the new attempt starts, so a
                // fresh capsule gets a fresh withdrawal.
                try? await Task.sleep(for: .seconds(4))
                withAnimation(policy.fade(Motion.stateFadeAnimation)) {
                    withdraw()
                }
            }
    }
}
