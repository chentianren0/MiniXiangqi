import UIKit
import SwiftUI

// Probe 11 — the elements the state-layers scheme needs that probe8 did not define.
// Element heights depend only on container width and Dynamic Type step, so the device
// this runs on is irrelevant; it is run on an iOS 27.0 simulator for the same font stack.

func f(_ v: CGFloat) -> String { String(format: "%.2f", v) }
var OUT = ""
func r(_ s: String) { OUT += s + "\n"; print(s) }
func flush() {
    let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    try? OUT.write(to: d.appendingPathComponent("probe11.txt"), atomically: true, encoding: .utf8)
}

let SIZES: [(DynamicTypeSize, String)] = [
    (.xSmall, "xS"), (.small, "S"), (.medium, "M"), (.large, "L"),
    (.xLarge, "xL"), (.xxLarge, "xxL"), (.xxxLarge, "xxxL"),
    (.accessibility1, "AX1"), (.accessibility2, "AX2"), (.accessibility3, "AX3"),
    (.accessibility4, "AX4"), (.accessibility5, "AX5"),
]

// ---------- Accepted copy, verbatim from docs/interaction-design.md ----------
enum E {
    static let turnPrimary = "轮到红方"
    static let resultTitle = "红方获胜"
    static let resultReason = "黑方被将死"
    static let recordedLine = "已记录到历史"
    static let repetitionMsg = "局面已三次重复，可以和棋结束。"
    static let metaTerminal = "人机对局 · 我执黑 · 红方获胜 · 黑方被将死 · 137 步"
}

// --- baselines, identical to probe8, to confirm reproducibility ---
struct TurnStatus: View {
    var body: some View {
        HStack(spacing: 8) {
            Text(E.turnPrimary).font(.body)
            Text("AI").font(.subheadline).foregroundStyle(.secondary)
            Text("将军").font(.subheadline).bold()
            Spacer(minLength: 0)
        }.padding(.vertical, 8).padding(.horizontal, 16)
    }
}
struct ResultCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(E.resultTitle).font(.title2).bold()
            Text(E.resultReason).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("悔棋") {}.buttonStyle(.bordered)
                Button("结束对局") {}.buttonStyle(.borderedProminent)
            }
        }.padding(16)
    }
}
struct ResultCardRecorded: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(E.resultTitle).font(.title2).bold()
            Text(E.recordedLine).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("回放") {}.buttonStyle(.bordered)
                Button("完成") {}.buttonStyle(.borderedProminent)
            }
        }.padding(16)
    }
}

// --- new: the card with its actions stacked, which is what an alert does at AX sizes ---
struct ResultCardStacked: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(E.resultTitle).font(.title2).bold()
            Text(E.resultReason).font(.subheadline).foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Button("悔棋") {}.buttonStyle(.bordered)
                Button("结束对局") {}.buttonStyle(.borderedProminent)
            }
        }.padding(16)
    }
}
// --- new: Free Play's card, which must keep 翻转棋盘 live per :214 "at any time" ---
struct ResultCardFree: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(E.resultTitle).font(.title2).bold()
            Text(E.resultReason).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("悔棋") {}.buttonStyle(.bordered)
                Button("翻转棋盘") {}.buttonStyle(.bordered)
                Button("结束对局") {}.buttonStyle(.borderedProminent)
            }
        }.padding(16)
    }
}
// --- new: the card carrying the accepted terminal metadata line (:340) ---
struct ResultCardMeta: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(E.resultTitle).font(.title2).bold()
            Text(E.resultReason).font(.subheadline).foregroundStyle(.secondary)
            Text(E.metaTerminal).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("悔棋") {}.buttonStyle(.bordered)
                Button("结束对局") {}.buttonStyle(.borderedProminent)
            }
        }.padding(16)
    }
}
// --- new: title + reason only, no actions (the "banner" split) ---
struct ResultBanner: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(E.resultTitle).font(.title2).bold()
            Text(E.resultReason).font(.subheadline).foregroundStyle(.secondary)
        }.padding(16)
    }
}
// --- new: the card's two actions as a standalone control row ---
struct ActionRow2: View {
    var body: some View {
        HStack(spacing: 12) {
            Button("悔棋") {}.buttonStyle(.bordered)
            Button("结束对局") {}.buttonStyle(.borderedProminent)
        }.controlSize(.large).padding(.vertical, 8).padding(.horizontal, 16)
    }
}
// --- new: Free Play's control row with the flip control moved out ---
struct ControlRow2Free: View {
    var body: some View {
        HStack(spacing: 12) { Button("悔棋") {}; Button("判和") {} }
            .buttonStyle(.bordered).controlSize(.large)
            .padding(.vertical, 8).padding(.horizontal, 16)
    }
}
// --- new: a standalone single-control flip row ---
struct FlipRow1: View {
    var body: some View {
        HStack { Button("翻转棋盘") {}.buttonStyle(.bordered).controlSize(.large); Spacer(minLength: 0) }
            .padding(.vertical, 8).padding(.horizontal, 16)
    }
}
// --- new: turn status with a trailing icon-only flip control on the same row ---
struct StatusPlusFlip: View {
    var body: some View {
        HStack(spacing: 8) {
            Text(E.turnPrimary).font(.body)
            Text("AI").font(.subheadline).foregroundStyle(.secondary)
            Text("将军").font(.subheadline).bold()
            Spacer(minLength: 0)
            Button { } label: { Image(systemName: "arrow.up.arrow.down") }
                .buttonStyle(.bordered)
        }.padding(.vertical, 8).padding(.horizontal, 16)
    }
}
// --- new: Free Play's card with 翻转棋盘 as an icon-only action ---
struct ResultCardFreeIcon: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(E.resultTitle).font(.title2).bold()
            Text(E.resultReason).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("悔棋") {}.buttonStyle(.bordered)
                Button { } label: { Image(systemName: "arrow.up.arrow.down") }.buttonStyle(.bordered)
                Button("结束对局") {}.buttonStyle(.borderedProminent)
            }
        }.padding(16)
    }
}
// --- new: Free Play's card with the flip icon on the title row ---
struct ResultCardFreeTitleIcon: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(E.resultTitle).font(.title2).bold()
                Spacer(minLength: 8)
                Button { } label: { Image(systemName: "arrow.up.arrow.down") }.buttonStyle(.bordered)
            }
            Text(E.resultReason).font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("悔棋") {}.buttonStyle(.bordered)
                Button("结束对局") {}.buttonStyle(.borderedProminent)
            }
        }.padding(16)
    }
}
// --- new: Free Play's turn status, which omits the AI controller label (:270) ---
struct TurnStatusFree: View {
    var body: some View {
        HStack(spacing: 8) {
            Text(E.turnPrimary).font(.body)
            Text("将军").font(.subheadline).bold()
            Spacer(minLength: 0)
        }.padding(.vertical, 8).padding(.horizontal, 16)
    }
}
// --- new: Free Play's status row with the flip control as an icon ---
struct TurnStatusFreePlusFlip: View {
    var body: some View {
        HStack(spacing: 8) {
            Text(E.turnPrimary).font(.body)
            Text("将军").font(.subheadline).bold()
            Spacer(minLength: 0)
            Button { } label: { Image(systemName: "arrow.up.arrow.down") }.buttonStyle(.bordered)
        }.padding(.vertical, 8).padding(.horizontal, 16)
    }
}
// --- baselines from probe8, remeasured here so both runs share one harness ---
struct ControlRowAI: View {
    var body: some View {
        HStack(spacing: 12) { Button("悔棋") {}; Button("判和") {}; Button("认输") {} }
            .buttonStyle(.bordered).controlSize(.large)
            .padding(.vertical, 8).padding(.horizontal, 16)
    }
}
struct ControlRowFree: View {
    var body: some View {
        HStack(spacing: 12) { Button("悔棋") {}; Button("判和") {}; Button("翻转棋盘") {} }
            .buttonStyle(.bordered).controlSize(.large)
            .padding(.vertical, 8).padding(.horizontal, 16)
    }
}
struct MoveRow: View {
    var body: some View {
        HStack { Text("12.").font(.footnote).monospacedDigit().foregroundStyle(.secondary)
                 Text("炮二平五").font(.body); Spacer(minLength: 0) }
            .padding(.vertical, 6).padding(.horizontal, 16)
    }
}
struct Transport6: View {
    var body: some View {
        HStack(spacing: 16) {
            ForEach(["backward.end.fill","backward.fill","play.fill","forward.fill","forward.end.fill","arrow.up.arrow.down"], id: \.self) { n in
                Button { } label: { Image(systemName: n) }
            }
        }.buttonStyle(.bordered).controlSize(.large)
         .padding(.vertical, 8).padding(.horizontal, 16)
    }
}
struct TransportPlusSpeed: View {
    var body: some View {
        VStack(spacing: 8) {
            Transport6()
            Picker("", selection: .constant(1)) { Text("0.5×").tag(0); Text("1×").tag(1); Text("2×").tag(2) }
                .pickerStyle(.segmented).padding(.horizontal, 16)
        }
    }
}
// --- new: the status row as the move list's summoning affordance (a disclosure row) ---
struct StatusDisclosureAI: View {
    var body: some View {
        HStack(spacing: 8) {
            Text(E.turnPrimary).font(.body)
            Text("AI").font(.subheadline).foregroundStyle(.secondary)
            Text("将军").font(.subheadline).bold()
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
        }.padding(.vertical, 8).padding(.horizontal, 16)
    }
}
// --- new: Free Play's status row: flip control + the same disclosure ---
struct StatusDisclosureFreeFlip: View {
    var body: some View {
        HStack(spacing: 8) {
            Text(E.turnPrimary).font(.body)
            Text("将军").font(.subheadline).bold()
            Spacer(minLength: 8)
            Button { } label: { Image(systemName: "arrow.up.arrow.down") }.buttonStyle(.bordered)
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
        }.padding(.vertical, 8).padding(.horizontal, 16)
    }
}
// --- new: replay's own progress row, with the same disclosure ---
struct ReplayStatusDisclosure: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("第 12 步 / 共 42 步").font(.body)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
        }.padding(.vertical, 8).padding(.horizontal, 16)
    }
}
struct ReplayStatusPlain: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("第 12 步 / 共 42 步").font(.body)
            Spacer(minLength: 0)
        }.padding(.vertical, 8).padding(.horizontal, 16)
    }
}
struct Transport7: View {
    var body: some View {
        HStack(spacing: 16) {
            ForEach(["backward.end.fill","backward.fill","play.fill","forward.fill","forward.end.fill","arrow.up.arrow.down","list.bullet"], id: \.self) { n in
                Button { } label: { Image(systemName: n) }
            }
        }.buttonStyle(.bordered).controlSize(.large)
         .padding(.vertical, 8).padding(.horizontal, 16)
    }
}
struct Transport7PlusSpeed: View {
    var body: some View {
        VStack(spacing: 8) {
            Transport7()
            Picker("", selection: .constant(1)) { Text("0.5×").tag(0); Text("1×").tag(1); Text("2×").tag(2) }
                .pickerStyle(.segmented).padding(.horizontal, 16)
        }
    }
}
// --- new: the threefold notice's own actions, for the alert-vs-inline comparison ---
struct Repetition: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(E.repetitionMsg).font(.body)
            HStack(spacing: 12) {
                Button("继续对局") {}.buttonStyle(.bordered)
                Button("以和棋结束") {}.buttonStyle(.borderedProminent)
            }
        }.padding(16)
    }
}

let WIDTHS: [CGFloat] = [264, 280, 296, 308, 320, 328, 335, 343, 351, 359, 367, 375,
                         382, 388, 398, 404, 424, 444, 500, 600, 686, 720]

func measure(_ name: String, _ v: some View, _ dts: DynamicTypeSize, _ label: String) {
    let hc = UIHostingController(rootView: AnyView(v.dynamicTypeSize(dts)))
    let inf = CGFloat.greatestFiniteMagnitude
    let ideal = hc.sizeThatFits(in: CGSize(width: inf, height: inf))
    var s = "E[\(label)] \(name) idealW=\(f(ideal.width)) idealH=\(f(ideal.height))"
    for w in WIDTHS {
        let h = hc.sizeThatFits(in: CGSize(width: w, height: inf)).height
        s += " h@\(Int(w))=\(f(h))"
    }
    r(s)
}

final class AD: UIResponder, UIApplicationDelegate {
    func application(_ a: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { true }
    func application(_ a: UIApplication, configurationForConnecting s: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: "Default", sessionRole: s.role); c.delegateClass = SD.self; return c
    }
}

final class SD: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: ws)
        w.rootViewController = UIHostingController(rootView: Color.clear)
        w.makeKeyAndVisible(); window = w
        r("DEVICE model=\(UIDevice.current.model) os=\(UIDevice.current.systemVersion) screen=\(f(ws.screen.bounds.width))x\(f(ws.screen.bounds.height))")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            for (dts, label) in SIZES {
                measure("turnStatus", TurnStatus(), dts, label)
                measure("resultCard", ResultCard(), dts, label)
                measure("resultCardRecorded", ResultCardRecorded(), dts, label)
                measure("resultCardStacked", ResultCardStacked(), dts, label)
                measure("resultCardFree", ResultCardFree(), dts, label)
                measure("resultCardMeta", ResultCardMeta(), dts, label)
                measure("resultBanner", ResultBanner(), dts, label)
                measure("actionRow2", ActionRow2(), dts, label)
                measure("controlRow2Free", ControlRow2Free(), dts, label)
                measure("flipRow1", FlipRow1(), dts, label)
                measure("statusPlusFlip", StatusPlusFlip(), dts, label)
                measure("resultCardFreeIcon", ResultCardFreeIcon(), dts, label)
                measure("resultCardFreeTitleIcon", ResultCardFreeTitleIcon(), dts, label)
                measure("turnStatusFree", TurnStatusFree(), dts, label)
                measure("turnStatusFreePlusFlip", TurnStatusFreePlusFlip(), dts, label)
                measure("controlRowAI", ControlRowAI(), dts, label)
                measure("controlRowFree", ControlRowFree(), dts, label)
                measure("moveListRow", MoveRow(), dts, label)
                measure("transport6", Transport6(), dts, label)
                measure("transportPlusSpeed", TransportPlusSpeed(), dts, label)
                measure("statusDisclosureAI", StatusDisclosureAI(), dts, label)
                measure("statusDisclosureFreeFlip", StatusDisclosureFreeFlip(), dts, label)
                measure("replayStatusDisclosure", ReplayStatusDisclosure(), dts, label)
                measure("replayStatusPlain", ReplayStatusPlain(), dts, label)
                measure("transport7", Transport7(), dts, label)
                measure("transport7PlusSpeed", Transport7PlusSpeed(), dts, label)
                measure("repetitionNotice", Repetition(), dts, label)
                r("---")
            }
            r("@@DONE11@@"); flush()
        }
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AD.self))
