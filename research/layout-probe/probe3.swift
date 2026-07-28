import UIKit
import SwiftUI

// Probe 3: accepted-copy element sizes (for the panel-minimum derivation),
// and what UISceneSizeRestrictions actually is on each idiom.

func f3(_ v: CGFloat) -> String { String(format: "%.2f", v) }
var O3 = ""
func r(_ s: String) { O3 += s + "\n"; print(s) }
func flush3() {
    let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    try? O3.write(to: d.appendingPathComponent("probe3.txt"), atomically: true, encoding: .utf8)
}

// Accepted copy, verbatim from docs/interaction-design.md on main.
struct E {
    static let turnStatusPrimary = "轮到红方"
    static let turnStatusFull = "轮到红方 · AI · 将军"
    static let resultTitle = "红方获胜"
    static let resultReason = "黑方被将死"
    static let repetitionMsg = "局面已三次重复，可以和棋结束。"
    static let metaOngoing = "人机对局 · 我执红 · 轮到黑方 · 可判和 · 42 步"
    static let metaTerminal = "人机对局 · 我执黑 · 红方获胜 · 黑方被将死 · 137 步"
    static let moveRow = "120.  炮二平五        马８进７"
}

struct TurnStatusA: View {
    var body: some View {
        HStack(spacing: 8) {
            Text(E.turnStatusPrimary).font(.body)
            Text("AI").font(.subheadline).foregroundStyle(.secondary)
            Text("将军").font(.subheadline).bold()
            Spacer(minLength: 0)
        }.padding(.vertical, 8).padding(.horizontal, 16)
    }
}
struct ControlRowA: View {
    var body: some View {
        HStack(spacing: 12) { Button("悔棋") {}; Button("判和") {}; Button("认输") {} }
            .buttonStyle(.bordered).controlSize(.large)
            .padding(.vertical, 8).padding(.horizontal, 16)
    }
}
struct ResultCardA: View {
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
struct ResultCardRecordedA: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(E.resultTitle).font(.title2).bold()
            Text("已记录到历史").font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("回放") {}.buttonStyle(.bordered)
                Button("完成") {}.buttonStyle(.borderedProminent)
            }
        }.padding(16)
    }
}
struct RepetitionA: View {
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
struct TransportA: View {
    var body: some View {
        HStack(spacing: 16) {
            ForEach(["backward.end.fill","backward.fill","play.fill","forward.fill","forward.end.fill","arrow.up.arrow.down"], id: \.self) { n in
                Button { } label: { Image(systemName: n) }
            }
        }.buttonStyle(.bordered).controlSize(.large)
         .padding(.vertical, 8).padding(.horizontal, 16)
    }
}
struct TransportPlusSpeedA: View {
    var body: some View {
        VStack(spacing: 8) {
            TransportA()
            Picker("", selection: .constant(1)) { Text("0.5×").tag(0); Text("1×").tag(1); Text("2×").tag(2) }
                .pickerStyle(.segmented).padding(.horizontal, 16)
        }
    }
}
struct MoveRowA: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("120.").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
            Text("炮二平五").padding(.leading, 12)
            Spacer(minLength: 16)
            Text("马８进７")
        }.font(.body).padding(.vertical, 6).padding(.horizontal, 16)
    }
}
struct MetaOngoingA: View {
    var body: some View { Text(E.metaOngoing).font(.footnote).lineLimit(1).padding(.horizontal, 16) }
}
struct MetaTerminalA: View {
    var body: some View { Text(E.metaTerminal).font(.footnote).lineLimit(1).padding(.horizontal, 16) }
}

func m3(_ name: String, _ v: some View, _ dts: DynamicTypeSize, _ label: String) {
    let hc = UIHostingController(rootView: AnyView(v.dynamicTypeSize(dts)))
    let ideal = hc.sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
    var s = "E3[\(label)] \(name) idealW=\(f3(ideal.width)) idealH=\(f3(ideal.height))"
    for w: CGFloat in [276, 308, 328, 343, 359, 375, 400, 480] {
        let h = hc.sizeThatFits(in: CGSize(width: w, height: CGFloat.greatestFiniteMagnitude)).height
        s += " h@\(Int(w))=\(f3(h))"
    }
    r(s)
}

final class AD3: UIResponder, UIApplicationDelegate {
    func application(_ a: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool { true }
    func application(_ a: UIApplication, configurationForConnecting s: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let c = UISceneConfiguration(name: "Default", sessionRole: s.role); c.delegateClass = SD3.self; return c
    }
}

final class SD3: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let ws = scene as? UIWindowScene else { return }
        let w = UIWindow(windowScene: ws); w.rootViewController = UIViewController(); w.makeKeyAndVisible(); window = w
        let idiom = w.traitCollection.userInterfaceIdiom == .pad ? "pad" : "phone"
        r("IDIOM=\(idiom) os=\(UIDevice.current.systemVersion) screen=\(f3(ws.screen.bounds.width))x\(f3(ws.screen.bounds.height))")

        // What does the platform actually offer for a declared minimum scene size?
        if let sr = ws.sizeRestrictions {
            r("sizeRestrictions AVAILABLE: minimumSize=\(f3(sr.minimumSize.width))x\(f3(sr.minimumSize.height)) maximumSize=\(f3(sr.maximumSize.width))x\(f3(sr.maximumSize.height)) allowsFullScreen=\(sr.allowsFullScreen)")
            sr.minimumSize = CGSize(width: 380, height: 500)
            r("after setting 380x500: minimumSize=\(f3(sr.minimumSize.width))x\(f3(sr.minimumSize.height))")
        } else {
            r("sizeRestrictions is NIL on this idiom — the app cannot declare a minimum scene size here")
        }
        r("scene effectiveGeometry=\(f3(ws.effectiveGeometry.coordinateSpace.bounds.width))x\(f3(ws.effectiveGeometry.coordinateSpace.bounds.height))")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            for (dts, label) in [(DynamicTypeSize.large, "L"),
                                 (DynamicTypeSize.xxxLarge, "xxxL"),
                                 (DynamicTypeSize.accessibility1, "AX1"),
                                 (DynamicTypeSize.accessibility3, "AX3"),
                                 (DynamicTypeSize.accessibility5, "AX5")] {
                m3("turnStatus", TurnStatusA(), dts, label)
                m3("controlRow", ControlRowA(), dts, label)
                m3("resultCard", ResultCardA(), dts, label)
                m3("resultCardRecorded", ResultCardRecordedA(), dts, label)
                m3("repetitionNotice", RepetitionA(), dts, label)
                m3("transport", TransportA(), dts, label)
                m3("transportPlusSpeed", TransportPlusSpeedA(), dts, label)
                m3("moveListRow", MoveRowA(), dts, label)
                m3("metaOngoing", MetaOngoingA(), dts, label)
                m3("metaTerminal", MetaTerminalA(), dts, label)
                r("---")
            }
            r("@@DONE3@@"); flush3()
        }
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AD3.self))
