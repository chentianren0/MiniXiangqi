import UIKit
import SwiftUI

// Probe 7 — History-row layout measurement.
// (a) measured content width available to a List row at a fixed container width;
// (b) measured heights of candidate History-row layouts at each Dynamic Type size,
//     in Simplified Chinese and English, at fixed content widths.

func f(_ v: CGFloat) -> String { String(format: "%.2f", v) }
var OUT = ""
func r(_ s: String) { OUT += s + "\n"; print(s) }
func flush() {
    let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    try? OUT.write(to: d.appendingPathComponent("probe7.txt"), atomically: true, encoding: .utf8)
}

// ---------- copy under test ----------
enum ZH {
    static let dateToday = "今天 14:32"
    static let dateOld = "2025/12/31 23:59"
    static let modeAI = "人机对弈"
    static let modeFree = "自由对弈"
    static let sideRed = "你执红"
    static let resultRedWin = "红方获胜"
    static let reasonMate = "将死"
    static let reasonRepetition = "三次重复"
    static let reasonEarly = "提前结束"
    static let noResult = "未分胜负"
    static let moves42 = "42 步"
    static let moves118 = "118 步"
    static let imported = "导入"
    // longest realistic secondary line
    static let secondaryLongest = "自由对弈 · 和棋 · 三次重复 · 118 步"
    static let secondaryAI = "人机对弈 · 你执红 · 红方获胜 · 将死 · 42 步"
    static let secondaryEarly = "人机对弈 · 你执黑 · 未分胜负 · 提前结束 · 3 步"
}
enum EN {
    static let dateToday = "Today, 2:32 PM"
    static let dateOld = "12/31/25, 11:59 PM"
    static let secondaryLongest = "Free Play · Draw · Threefold repetition · 118 moves"
    static let secondaryAI = "Human vs AI · You played Red · Red wins · Checkmate · 42 moves"
    static let secondaryEarly = "Human vs AI · You played Black · No result · Ended early · 3 moves"
    static let imported = "Imported"
}

// ---------- candidate row layouts ----------

// Layout A — two lines: title line (date + badges), secondary line (mode · result · reason · moves)
struct RowA: View {
    let date: String, secondary: String, imported: String, pinned: Bool
    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(date).font(.body)
                    if !imported.isEmpty {
                        Label(imported, systemImage: "square.and.arrow.down")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(.quaternary))
                    }
                    Spacer(minLength: 0)
                    if pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary) }
                }
                Text(secondary).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 11).padding(.horizontal, 16)
    }
}

// Layout B — three lines: date; mode + side; result · reason · moves
struct RowB: View {
    let date: String, line2: String, line3: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(date).font(.body)
            Text(line2).font(.subheadline).foregroundStyle(.secondary)
            Text(line3).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 11).padding(.horizontal, 16)
    }
}

// Layout C — one line (rejected candidate, measured for comparison)
struct RowC: View {
    let all: String
    var body: some View {
        Text(all).font(.body).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 11).padding(.horizontal, 16)
    }
}

let categories: [(String, ContentSizeCategory)] = [
    ("L", .large), ("xxxL", .extraExtraExtraLarge),
    ("AX1", .accessibilityMedium), ("AX3", .accessibilityExtraLarge),
    ("AX5", .accessibilityExtraExtraExtraLarge),
]

func height<V: View>(_ v: V, width: CGFloat, cat: ContentSizeCategory) -> CGFloat {
    let host = UIHostingController(rootView: AnyView(v.environment(\.sizeCategory, cat)))
    host.view.backgroundColor = .clear
    return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
}

// measure how many lines a string needs at a given width/font
func lineCount(_ s: String, font: UIFont, width: CGFloat) -> Int {
    let attr = NSAttributedString(string: s, attributes: [.font: font])
    let box = attr.boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
    return max(1, Int((box.height / font.lineHeight).rounded()))
}

final class VC: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        r("=== probe7: History row measurement ===")
        r("device=\(UIDevice.current.name) ios=\(UIDevice.current.systemVersion)")
        r("screen=\(f(UIScreen.main.bounds.width))x\(f(UIScreen.main.bounds.height))")
        r("")

        // ---- (a) List row content width at container width 375 ----
        r("--- (a) list geometry, container width 375 ---")
        for style in ["plain", "insetGrouped-equivalent"] {
            r("  style \(style): measured below via UICollectionLayoutListConfiguration")
        }
        for appearance in [UICollectionLayoutListConfiguration.Appearance.plain,
                           .grouped, .insetGrouped, .sidebar] {
            var cfg = UICollectionLayoutListConfiguration(appearance: appearance)
            cfg.showsSeparators = true
            let layout = UICollectionViewCompositionalLayout.list(using: cfg)
            let cv = UICollectionView(frame: CGRect(x: 0, y: 0, width: 375, height: 600),
                                      collectionViewLayout: layout)
            let reg = UICollectionView.CellRegistration<UICollectionViewListCell, Int> { cell, _, _ in
                var c = cell.defaultContentConfiguration()
                c.text = ZH.dateToday
                c.secondaryText = ZH.secondaryAI
                cell.contentConfiguration = c
            }
            let ds = UICollectionViewDiffableDataSource<Int, Int>(collectionView: cv) { cv, ip, item in
                cv.dequeueConfiguredReusableCell(using: reg, for: ip, item: item)
            }
            var snap = NSDiffableDataSourceSnapshot<Int, Int>()
            snap.appendSections([0]); snap.appendItems([0, 1, 2])
            ds.apply(snap, animatingDifferences: false)
            view.addSubview(cv)
            cv.layoutIfNeeded()
            let attrs = layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))
            let cellW = attrs?.frame.width ?? -1
            let cellX = attrs?.frame.origin.x ?? -1
            let cellH = attrs?.frame.height ?? -1
            var contentW: CGFloat = -1
            if let cell = cv.cellForItem(at: IndexPath(item: 0, section: 0)) as? UICollectionViewListCell,
               let cv2 = cell.contentView.subviews.first {
                contentW = cv2.frame.width
            }
            let name: String
            switch appearance {
            case .plain: name = "plain"
            case .grouped: name = "grouped"
            case .insetGrouped: name = "insetGrouped"
            case .sidebar: name = "sidebar"
            default: name = "other"
            }
            r("  \(name): cell x=\(f(cellX)) w=\(f(cellW)) h=\(f(cellH)) innerContentW=\(f(contentW))")
            cv.removeFromSuperview()
        }
        r("")

        // ---- (b) candidate row heights ----
        let widths: [CGFloat] = [375, 343, 311]
        r("--- (b) candidate row heights, zh-Hans copy ---")
        for w in widths {
            r("  content width \(f(w)):")
            for (label, cat) in categories {
                let a = height(RowA(date: ZH.dateToday, secondary: ZH.secondaryAI,
                                    imported: "", pinned: false), width: w, cat: cat)
                let aImp = height(RowA(date: ZH.dateOld, secondary: ZH.secondaryLongest,
                                       imported: ZH.imported, pinned: true), width: w, cat: cat)
                let b = height(RowB(date: ZH.dateToday, line2: "人机对弈 · 你执红",
                                    line3: "红方获胜 · 将死 · 42 步"), width: w, cat: cat)
                let c = height(RowC(all: "\(ZH.dateToday) · \(ZH.secondaryAI)"), width: w, cat: cat)
                r("    \(label): A=\(f(a))  A+imported+pin=\(f(aImp))  B=\(f(b))  C(1line)=\(f(c))")
            }
        }
        r("")
        r("--- (b) candidate row heights, en copy ---")
        for w in widths {
            r("  content width \(f(w)):")
            for (label, cat) in categories {
                let a = height(RowA(date: EN.dateToday, secondary: EN.secondaryAI,
                                    imported: "", pinned: false), width: w, cat: cat)
                let aImp = height(RowA(date: EN.dateOld, secondary: EN.secondaryLongest,
                                       imported: EN.imported, pinned: true), width: w, cat: cat)
                let b = height(RowB(date: EN.dateToday, line2: "Human vs AI · You played Red",
                                    line3: "Red wins · Checkmate · 42 moves"), width: w, cat: cat)
                r("    \(label): A=\(f(a))  A+imported+pin=\(f(aImp))  B=\(f(b))")
            }
        }
        r("")

        // ---- (c) how many lines the secondary string needs ----
        r("--- (c) secondary-line wrap count at subheadline, content width 343 minus 32 = 311 ---")
        for (label, cat) in categories {
            let traits = UITraitCollection(preferredContentSizeCategory:
                UIContentSizeCategory(rawValue: uiRaw(cat)))
            let font = UIFont.preferredFont(forTextStyle: .subheadline, compatibleWith: traits)
            let zhA = lineCount(ZH.secondaryAI, font: font, width: 311)
            let zhL = lineCount(ZH.secondaryLongest, font: font, width: 311)
            let zhE = lineCount(ZH.secondaryEarly, font: font, width: 311)
            let enA = lineCount(EN.secondaryAI, font: font, width: 311)
            let enL = lineCount(EN.secondaryLongest, font: font, width: 311)
            let enE = lineCount(EN.secondaryEarly, font: font, width: 311)
            r("    \(label) (pt=\(f(font.pointSize))): zh AI=\(zhA) longest=\(zhL) early=\(zhE) | en AI=\(enA) longest=\(enL) early=\(enE)")
        }
        r("")

        // ---- (d) 44 pt floor check ----
        r("--- (d) does layout A clear the 44 pt hit-target floor at L? ---")
        let aL = height(RowA(date: ZH.dateToday, secondary: ZH.secondaryAI, imported: "", pinned: false),
                        width: 343, cat: .large)
        r("    A at L, width 343 = \(f(aL)) pt  (floor 44)")
        r("")

        flush()
    }
}

func uiRaw(_ c: ContentSizeCategory) -> String {
    switch c {
    case .large: return UIContentSizeCategory.large.rawValue
    case .extraExtraExtraLarge: return UIContentSizeCategory.extraExtraExtraLarge.rawValue
    case .accessibilityMedium: return UIContentSizeCategory.accessibilityMedium.rawValue
    case .accessibilityExtraLarge: return UIContentSizeCategory.accessibilityExtraLarge.rawValue
    case .accessibilityExtraExtraExtraLarge: return UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
    default: return UIContentSizeCategory.large.rawValue
    }
}

class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    func application(_ a: UIApplication, didFinishLaunchingWithOptions o: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = VC()
        window?.makeKeyAndVisible()
        return true
    }
}

UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(AppDelegate.self))
