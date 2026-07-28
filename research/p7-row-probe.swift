import UIKit
import SwiftUI

// p7-row-probe — (i) does splitting the dot-joined secondary line into one line per
// segment cost or save height at accessibility text sizes?  (ii) do the SF Symbols
// the swipe actions need exist, including their auto-applied .fill variants?
// (iii) exact widths of the proposed line-1 strings.

func f(_ v: CGFloat) -> String { String(format: "%.2f", v) }
var OUT = ""
func r(_ s: String) { OUT += s + "\n"; print(s) }
func flush() {
    let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    try? OUT.write(to: d.appendingPathComponent("p7row.txt"), atomically: true, encoding: .utf8)
}

let zhSegs = ["人机对弈", "你执黑", "未分胜负", "提前结束", "3 步"]
let zhSegsDraw = ["自由对弈", "和棋", "三次重复", "118 步"]
let enSegs = ["Human vs AI", "You played Black", "No result", "Ended early", "3 moves"]
let enSegsDraw = ["Free Play", "Draw", "Threefold repetition", "118 moves"]

struct Joined: View {
    let date: String, segs: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(date).font(.body)
            Text(segs.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 11).padding(.horizontal, 16)
    }
}
struct Split: View {
    let date: String, segs: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(date).font(.body)
            ForEach(segs, id: \.self) { s in
                Text(s).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 11).padding(.horizontal, 16)
    }
}

let cats: [(String, ContentSizeCategory)] = [
    ("L", .large), ("xxxL", .extraExtraExtraLarge),
    ("AX1", .accessibilityMedium), ("AX3", .accessibilityExtraLarge),
    ("AX5", .accessibilityExtraExtraExtraLarge),
]

func h<V: View>(_ v: V, _ w: CGFloat, _ c: ContentSizeCategory) -> CGFloat {
    UIHostingController(rootView: AnyView(v.environment(\.sizeCategory, c)))
        .sizeThatFits(in: CGSize(width: w, height: .greatestFiniteMagnitude)).height
}

final class VC: UIViewController {
    override func viewDidAppear(_ a: Bool) {
        super.viewDidAppear(a)
        r("=== p7-row-probe ===")
        r("ios=\(UIDevice.current.systemVersion)")
        r("")
        r("--- (i) joined vs split secondary line, cell width 343 (= 375 pt device, insetGrouped) ---")
        for (name, date, segs) in [
            ("zh worst (ended early)", "2026/7/22 18:45", zhSegs),
            ("zh draw", "2026/7/22 18:45", zhSegsDraw),
            ("en worst (ended early)", "7/22/2026, 6:45 PM", enSegs),
            ("en draw", "7/22/2026, 6:45 PM", enSegsDraw),
        ] {
            r("  \(name):")
            for (label, cat) in cats {
                let j = h(Joined(date: date, segs: segs), 343, cat)
                let s = h(Split(date: date, segs: segs), 343, cat)
                r("    \(label): joined=\(f(j))  split=\(f(s))  split-joined=\(f(s - j))")
            }
        }
        r("")
        r("--- (ii) SF Symbols required by the swipe actions and the imported marker ---")
        for n in ["square.and.arrow.up", "square.and.arrow.up.fill",
                  "square.and.arrow.down", "square.and.arrow.down.fill",
                  "trash", "trash.fill", "pin", "pin.fill",
                  "pin.slash", "pin.slash.fill", "arrow.down.doc", "tray.and.arrow.down"] {
            r("    \(n): \(UIImage(systemName: n) != nil ? "EXISTS" : "MISSING")")
        }
        r("")
        r("--- (iii) exact widths of proposed line-1 strings (body, default size) ---")
        let bodyFont = UIFont.preferredFont(forTextStyle: .body,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large))
        r("    body point size = \(f(bodyFont.pointSize))")
        for s in ["今天 14:32", "昨天 21:05", "2026/7/22 18:45", "2025/12/31 23:59",
                  "导入 · 今天 14:32", "导入 · 2024/11/9 12:00",
                  "Today at 2:32 PM", "Yesterday at 9:05 PM",
                  "7/22/2026, 6:45 PM", "12/31/2025, 11:59 PM",
                  "Imported · Today at 2:32 PM", "Imported · 11/9/2024, 12:00 PM"] {
            let w = (s as NSString).size(withAttributes: [.font: bodyFont]).width
            r("    w=\(f(w))  \(s)   (available 311)")
        }
        r("")
        r("--- (iv) same strings at AX5 body ---")
        let ax5 = UIFont.preferredFont(forTextStyle: .body,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge))
        r("    AX5 body point size = \(f(ax5.pointSize))")
        for s in ["导入 · 2024/11/9 12:00", "Imported · 11/9/2024, 12:00 PM"] {
            let w = (s as NSString).size(withAttributes: [.font: ax5]).width
            r("    w=\(f(w))  \(s)   (available 311)")
        }
        flush()
    }
}

class AD: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ a: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = VC(); window?.makeKeyAndVisible(); return true
    }
}
UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AD.self))
