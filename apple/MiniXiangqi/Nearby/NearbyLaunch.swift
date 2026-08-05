// The launch arguments the nearby developer harness takes.
//
// A two-device run is driven from a terminal — `devicectl device process
// launch --console … -- <args>` — and that is the *whole* of what can reach a
// physical device from here: Xcode's device interaction drives simulators only,
// and Wi-Fi Aware does not exist on a simulator. So everything a driven run
// needs the harness to do, it says here, and the screen's own controls are for
// a person standing in front of the device.
//
// Debug builds only, like every other launch argument in this app: a release
// build compiles none of it, and there is no other way in.

#if DEBUG
import Foundation

struct NearbyLaunch: Equatable {
    /// One thing a driven run asks this device to do of its own accord, once
    /// its scripted line has run out.
    enum Intent: String, Equatable {
        case offerDraw = "offer-draw"
        case resign
        case claim
    }

    /// `-mxq-open-nearby` — opens the developer screen in place of the app.
    /// The harness has no public entry anywhere else.
    var opensHarness = false
    /// `-mxq-nearby-autostart` — publishes and subscribes on launch, so a
    /// driven run does not need a tap to get the radio up.
    var autostarts = false
    /// `-mxq-nearby-script b1b2,b7b6,…` — a known line, played one ply at a
    /// time on whichever device owes the next one.
    var script: [String] = []
    /// `-mxq-nearby-propose minixiangqi:first` — offer that game, taking that
    /// mover, to a device this one holds no live session with.
    var proposal: Proposal?
    /// `-mxq-nearby-consent` — accept an arriving proposal.
    var consents = false
    /// `-mxq-nearby-agree` — accept a draw offer or an undo request that
    /// stands.
    var agrees = false
    /// `-mxq-nearby-autoplay` — play the scripted line's next ply whenever it
    /// is this device's turn.
    var autoplays = false
    /// `-mxq-nearby-then resign` — and when the line has run out, this.
    var then: Intent?
    /// `-mxq-nearby-resume` — take up the interrupted nearby game the library
    /// holds, and continue the session it was played over. It stands in for the
    /// player's own tap on the Play home's card, which is what starts recovery
    /// in the app: a driven run has no hands, and the entry decision is that
    /// nothing enters a nearby game by itself.
    var resumesStoredGame = false

    struct Proposal: Equatable {
        var rulesID: String
        var proposerMoves: Mover
    }

    init(arguments: [String]) {
        opensHarness = arguments.contains("-mxq-open-nearby")
        autostarts = arguments.contains("-mxq-nearby-autostart")
        consents = arguments.contains("-mxq-nearby-consent")
        agrees = arguments.contains("-mxq-nearby-agree")
        autoplays = arguments.contains("-mxq-nearby-autoplay")
        resumesStoredGame = arguments.contains("-mxq-nearby-resume")
        script = Self.line(after: "-mxq-nearby-script", in: arguments)
        proposal = Self.proposal(in: Self.value(after: "-mxq-nearby-propose", in: arguments))
        then = Self.value(after: "-mxq-nearby-then", in: arguments).flatMap(Intent.init(rawValue:))
    }

    /// This process's own arguments.
    static var current: Self { Self(arguments: ProcessInfo.processInfo.arguments) }

    /// The move at that point of the line, where the line reaches that far.
    func move(at index: Int) -> String? {
        script.indices.contains(index) ? script[index] : nil
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let flagIndex = arguments.firstIndex(of: flag) else { return nil }
        let valueIndex = arguments.index(after: flagIndex)
        guard valueIndex < arguments.endIndex else { return nil }
        return arguments[valueIndex]
    }

    /// A comma-separated line, with the spaces a shell quote leaves behind
    /// trimmed and empty pieces dropped — `"b1b2, b7b6"` is the same line as
    /// `"b1b2,b7b6"`, and a trailing comma is not a ply.
    private static func line(after flag: String, in arguments: [String]) -> [String] {
        guard let value = value(after: flag, in: arguments) else { return [] }
        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// `<rules_id>:<first|second>`, and nothing at all where either half is
    /// missing or unknown.
    private static func proposal(in value: String?) -> Proposal? {
        guard let value else { return nil }
        let parts = value.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, !parts[0].isEmpty,
              let moves = Mover(rawValue: String(parts[1]))
        else { return nil }
        return Proposal(rulesID: String(parts[0]), proposerMoves: moves)
    }
}
#endif
