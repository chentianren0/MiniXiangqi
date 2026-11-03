// A failed save on the player's own move is reported here and nowhere else:
// nothing modal, nothing on the board, because the board did not change.

import SwiftUI

struct SaveFailureCapsule: View {
    /// Called by the capsule's own clock, so the screen holding the flag is the
    /// one that lowers it.
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
            // A Mac has no warning haptic, so the symbol stands in for it.
            .onAppear {
                AccessibilityNotification
                    .Announcement(String(localized: "status.saveFailed"))
                    .post()
            }
            .task {
                // A second refusal re-raises it: the flag passes through false
                // as the new attempt starts, so a fresh capsule gets a fresh
                // withdrawal.
                try? await Task.sleep(for: .seconds(4))
                withAnimation(policy.fade(Motion.stateFadeAnimation)) {
                    withdraw()
                }
            }
    }
}
