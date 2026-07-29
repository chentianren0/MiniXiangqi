// The moves so far, in traditional notation, paired by full move.
//
// Where the side-by-side layout applies — ordinary Mac windows, iPad landscape
// — the move list is permanently visible in the panel. It is presentation:
// what is stored is the canonical notation, and this never shows it.

import SwiftUI

struct MoveList: View {
    var notation: [String]

    @Environment(\.motionPolicy) private var policy

    private var rows: [(number: Int, red: String, black: String?)] {
        stride(from: 0, to: notation.count, by: 2).map { index in
            (number: index / 2 + 1,
             red: notation[index],
             black: index + 1 < notation.count ? notation[index + 1] : nil)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(rows, id: \.number) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(row.number).")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 28, alignment: .trailing)
                            Text(row.red)
                                .frame(width: 76, alignment: .leading)
                            Text(row.black ?? "")
                                .frame(width: 76, alignment: .leading)
                        }
                        .font(.callout)
                        .id(row.number)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: notation.count) {
                guard let last = rows.last else { return }
                // An animated scroll is movement with no crossfade to fall
                // back to, so under Reduce Motion it arrives immediately.
                withAnimation(policy.scroll(.default)) {
                    proxy.scrollTo(last.number, anchor: .bottom)
                }
            }
        }
    }
}
