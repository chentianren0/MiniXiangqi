// What a UI-test launch has to say about the preferences before it can be about
// anything else.
//
// **A launch that names no preference is not a launch at the defaults.** The app
// reads its preferences through `Preferences.defaults`, and every persistent
// domain that object searches belongs to the machine the tests run on: the
// application's own domain is the operator's, and `-mxq-defaults-suite` adds a
// scratch domain *behind* it rather than in place of it — `UserDefaults` searches
// the application domain first and a suite after it. So a test that asserts the
// accepted default is asserting whatever the last person to open Settings chose,
// and one afternoon of the owner's own use is enough to turn a green suite red.
// It did: a full run failed 36 assertions across four suites, every one of them a
// notation reading or a deletion confirmation, because `notation.style` said
// `wxf` and `deleteConfirmation.enabled` said off in a domain no test had
// written.
//
// The argument domain is the answer, and it is the one the app's own contract
// already points at: `NSArgumentDomain` is searched **ahead of** every persistent
// domain, `-key value` on the command line is how it is filled, and nothing is
// written anywhere. So every launch states every preference — the accepted
// default, unless the test names its own — and what the app reads is then the
// launch's own answer rather than the machine's.
//
// The keys are `Settings/Preferences.swift`'s: this list is that table, and a
// preference added there without being added here is a preference the tests
// would go back to inheriting.
//
// **This file is the one thing both platforms' suites share, and it is
// deliberately the only one.** The bundle now builds for an iOS Simulator as
// well as for macOS — the Mac's suites are `#if os(macOS)` and the phone's are
// `#if os(iOS)`, because a window and a finger have almost nothing to say to
// each other — but the lesson above is not a macOS lesson. A Simulator's
// persistent domains belong to the machine the tests run on exactly as a Mac's
// do, so a phone launch that named no preference would inherit whatever the last
// run left behind, and there would then be two tables to keep in step instead of
// one. Nothing here is platform-specific, and nothing here may become so.

import Foundation

enum LaunchPreferences {
    /// Every preference the app keeps, at the value a new installation has.
    /// `Settings/Preferences.swift`'s table, in the vocabulary the keys are
    /// stored in; the two flags are `1`, which is what the argument domain can
    /// carry and what `Preferences.Flag` reads as a Bool.
    ///
    /// One of them is a *stated* state rather than the new-installation one, and
    /// deliberately: `notation.style` has no fixed default any more — it follows
    /// the interface language, WXF under English and the traditional reading
    /// under Chinese, by the owner's decision of 2026-07-30. Naming it here keeps
    /// every launch on one reading in both languages, which is what makes a
    /// screenshot comparable across them; a suite that wants to see the
    /// language's own answer has to leave the key to the domain, as the writing
    /// tests already do for other reasons.
    static let accepted = [
        "sound.enabled": "1",
        "haptics.enabled": "1",
        "deleteConfirmation.enabled": "1",
        // Off on a new installation, which is the accepted default for this one:
        // a tap places the stone, and the pending stone is what a player turns
        // on. A test that wants the confirmed grammar names it.
        "placementConfirmation.enabled": "0",
        "pieces.symbols": "hanzi",
        "notation.style": "traditional",
        "defaults.firstMover": "human-first",
        "defaults.aiLevel": "standard",
    ]

    /// The launch arguments that put a launch on a stated preference state.
    ///
    /// `overriding` is the state a test wants instead of the accepted default —
    /// the same thing the old per-suite `notation:` and `preferences:` parameters
    /// named, now in one place so a key cannot be stated twice in one launch.
    ///
    /// `leavingToTheDomain` is for the one thing the argument domain cannot do:
    /// a test about *writing* a preference has to be able to read back what it
    /// wrote, and a key named on the command line would outrank the click. Those
    /// keys are left out entirely, and the tests that leave them out are written
    /// not to depend on the state they start from.
    static func arguments(overriding overrides: [String: String] = [:],
                          leavingToTheDomain unpinned: Set<String> = []) -> [String] {
        accepted
            .merging(overrides) { _, override in override }
            .filter { !unpinned.contains($0.key) }
            // Sorted so that one launch's arguments are the same list every run,
            // which is what makes a failing run reproducible from its log.
            .sorted { $0.key < $1.key }
            .flatMap { ["-\($0.key)", $0.value] }
    }

    /// The scratch preference domain a launch writes into, for the suites whose
    /// tests do not write one deliberately. Nothing here is expected to write a
    /// preference; the domain exists so that an accidental write lands somewhere
    /// that is not the operator's.
    ///
    /// One fixed name rather than one per launch: a suite is a file in the app's
    /// preferences and nothing reclaims it, so a name minted per launch would
    /// leave a plist behind on every run, for ever.
    static let scratchSuite = "mxq-uitests-scratch"
}
