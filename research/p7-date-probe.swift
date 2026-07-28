// p7-date-probe.swift — locale-correct date formatting evidence for the History row.
// Executed on the pinned Xcode 27 beta toolchain. Read-only measurement; writes nothing.

import Foundation
#if canImport(AppKit)
import AppKit
#endif

let tz = TimeZone(identifier: "Asia/Shanghai")!
var cal = Calendar(identifier: .gregorian)
cal.timeZone = tz

func d(_ y: Int, _ mo: Int, _ da: Int, _ h: Int, _ mi: Int) -> Date {
    var c = DateComponents()
    c.year = y; c.month = mo; c.day = da; c.hour = h; c.minute = mi
    c.timeZone = tz
    return cal.date(from: c)!
}

// "now" for the relative probes
let now = d(2026, 7, 28, 15, 40)

let samples: [(String, Date)] = [
    ("same day, morning",   d(2026, 7, 28,  9,  5)),
    ("same day, afternoon", d(2026, 7, 28, 14, 32)),
    ("yesterday",           d(2026, 7, 27, 21, 5)),
    ("6 days ago",          d(2026, 7, 22, 18, 45)),
    ("this year, Jan",      d(2026, 1,  3,  7, 30)),
    ("last year, Dec",      d(2025, 12, 31, 23, 59)),
    ("older",               d(2024, 11,  9, 12,  0)),
    ("midnight",            d(2026, 7, 28,  0,  0)),
    ("noon",                d(2026, 7, 28, 12,  0)),
]

let locales = [Locale(identifier: "zh-Hans-CN"), Locale(identifier: "en-US"), Locale(identifier: "en-GB")]

#if canImport(AppKit)
func width(_ s: String, size: CGFloat = 15, weight: NSFont.Weight = .regular) -> CGFloat {
    let f = NSFont.systemFont(ofSize: size, weight: weight)
    return (s as NSString).size(withAttributes: [.font: f]).width
}
#else
func width(_ s: String, size: CGFloat = 15, weight: Int = 0) -> CGFloat { CGFloat(s.count) }
#endif

func w(_ s: String) -> String { String(format: "%.1f", width(s)) }

print("===== A. Date.FormatStyle presets, numeric/abbreviated date + shortened time =====")
for loc in locales {
    print("--- locale \(loc.identifier) ---")
    for (label, date) in samples {
        let numeric = date.formatted(
            Date.FormatStyle(date: .numeric, time: .shortened, locale: loc, calendar: cal, timeZone: tz))
        let abbrev = date.formatted(
            Date.FormatStyle(date: .abbreviated, time: .shortened, locale: loc, calendar: cal, timeZone: tz))
        let dateOnlyNum = date.formatted(
            Date.FormatStyle(date: .numeric, time: .omitted, locale: loc, calendar: cal, timeZone: tz))
        print(String(format: "  %-20@ | numeric+short: %@ (w=%@) | abbrev+short: %@ (w=%@) | dateonly: %@",
                     label as NSString, numeric, w(numeric), abbrev, w(abbrev), dateOnlyNum))
    }
}

print()
print("===== B. DateFormatter with doesRelativeDateFormatting = true =====")
for loc in locales {
    print("--- locale \(loc.identifier) ---")
    let df = DateFormatter()
    df.locale = loc
    df.calendar = cal
    df.timeZone = tz
    df.dateStyle = .medium
    df.timeStyle = .short
    df.doesRelativeDateFormatting = true

    let dfShort = DateFormatter()
    dfShort.locale = loc
    dfShort.calendar = cal
    dfShort.timeZone = tz
    dfShort.dateStyle = .short
    dfShort.timeStyle = .short
    dfShort.doesRelativeDateFormatting = true

    for (label, date) in samples {
        let a = df.string(from: date)
        let b = dfShort.string(from: date)
        print(String(format: "  %-20@ | medium+short rel: %@ (w=%@) | short+short rel: %@ (w=%@)",
                     label as NSString, a, w(a), b, w(b)))
    }
}

print()
print("===== C. Field-built styles (explicit components) =====")
for loc in locales {
    print("--- locale \(loc.identifier) ---")
    for (label, date) in samples {
        let ymdhm = date.formatted(
            .dateTime.year().month(.defaultDigits).day().hour().minute()
                .locale(loc))
        let mdhm = date.formatted(
            .dateTime.month(.defaultDigits).day().hour().minute().locale(loc))
        let ymd = date.formatted(.dateTime.year().month(.defaultDigits).day().locale(loc))
        print(String(format: "  %-20@ | y m d h m: %@ (w=%@) | m d h m: %@ (w=%@) | y m d: %@",
                     label as NSString, ymdhm, w(ymdhm), mdhm, w(mdhm), ymd))
    }
}

print()
print("===== D. Relative-only (information-losing) for comparison =====")
for loc in locales {
    let rf = RelativeDateTimeFormatter()
    rf.locale = loc
    rf.calendar = cal
    rf.dateTimeStyle = .named
    print("--- locale \(loc.identifier) ---")
    for (label, date) in samples {
        print("  \(label): \(rf.localizedString(for: date, relativeTo: now))")
    }
}

print()
print("===== E. 24-hour override check: does the locale honour system 24h? =====")
for id in ["zh-Hans-CN", "en-US", "en-GB"] {
    let loc = Locale(identifier: id)
    let fmt = DateFormatter.dateFormat(fromTemplate: "jm", options: 0, locale: loc) ?? "?"
    let fmtH = DateFormatter.dateFormat(fromTemplate: "Hm", options: 0, locale: loc) ?? "?"
    print("  \(id): template j m -> \(fmt) ; template H m -> \(fmtH)")
}

print()
print("===== F. Candidate row-string widths at body size (15 pt system) =====")
let rowStrings = [
    "人机对弈 · 你执红",
    "自由对弈",
    "红方获胜 · 将死 · 42 步",
    "黑方获弃 · 认输 · 7 步",
    "和棋 · 三次重复 · 118 步",
    "未分胜负 · 提前结束 · 3 步",
    "Human vs AI · You played Red",
    "Free Play",
    "Red wins · Checkmate · 42 moves",
    "Draw · Threefold repetition · 118 moves",
    "No result · Ended early · 3 moves",
]
for s in rowStrings { print("  w=\(w(s))  \(s)") }

print()
print("===== G. Move-count phrasing: plies vs moves =====")
for n in [1, 2, 3, 7, 42, 118, 9999, 10000] {
    let zh = "\(n) 步"
    let en = n == 1 ? "\(n) move" : "\(n) moves"
    print("  \(n): zh='\(zh)' (w=\(w(zh)))  en='\(en)' (w=\(w(en)))")
}

print()
print("===== H. Export default filename candidates =====")
let fnDate = d(2026, 7, 28, 14, 32)
let iso = DateFormatter()
iso.locale = Locale(identifier: "en_US_POSIX")
iso.timeZone = tz
iso.dateFormat = "yyyy-MM-dd-HHmm"
print("  stamp: \(iso.string(from: fnDate))")
print("  candidate: minixiangqi-\(iso.string(from: fnDate)).mxq")
