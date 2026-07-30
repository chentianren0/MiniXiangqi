// The preference contract, held to the letter.
//
// Issue #64's Stage 5 design fixes five keys, their types, and what each one's
// absence means, and says so as a table because three separate pieces of work
// read it: the screen that writes these keys, and the renderings that read them,
// are built apart. A key spelled differently in two of them is a preference that
// silently does nothing, which is the one failure a screenshot cannot show. So
// the spelling, the stored type, and the default are asserted here rather than
// trusted.
//
// Nothing here writes the standard database. Under a hosted unit run that is the
// application's own domain — the domain the player's real preferences live in —
// so every write goes to the suite's scratch domain, exactly as the sound gate's
// tests already did.

import Foundation
import Testing
@testable import MiniXiangqi

@Suite("The preferences the app keeps")
@MainActor
struct PreferencesTests {

    /// The three that are on or off. Each is asserted about individually where
    /// its own default matters and swept over where the claim is about the shape
    /// of a switch rather than about which switch it is.
    private static let switches: [Preferences.Flag] =
        [Preferences.sound, Preferences.haptics, Preferences.deleteConfirmation]

    @Test("Each preference is stored under the key the design fixes")
    func theKeysAreTheContractedOnes() {
        #expect(Preferences.sound.key == "sound.enabled")
        #expect(Preferences.haptics.key == "haptics.enabled")
        #expect(Preferences.deleteConfirmation.key == "deleteConfirmation.enabled")
        #expect(Preferences.pieceSymbols.key == "pieces.symbols")
        #expect(Preferences.notationStyle.key == "notation.style")

        // The stored names, which are as much of the contract as the keys are:
        // the renderings that read them are separate work and see nothing of
        // this file, only the string.
        #expect(Preferences.pieceSymbols.names == ["hanzi", "icons"])
        #expect(Preferences.notationStyle.names == ["traditional", "wxf"])
    }

    @Test("An absent key is the accepted default, which is the state of a first launch")
    func absenceMeansTheDefault() throws {
        let first = try ScratchDefaults.make()
        defer { ScratchDefaults.clear() }

        #expect(Preferences.sound.value(in: first), "sound on")
        #expect(Preferences.haptics.value(in: first), "haptics on")
        #expect(Preferences.deleteConfirmation.value(in: first), "and it asks before deleting")
        #expect(Preferences.pieceSymbols.value(in: first) == "hanzi")
        #expect(Preferences.notationStyle.value(in: first) == "traditional")

        // Said the other way round, because "absent" is a claim about the store
        // and not only about the answer: nothing has been written at all.
        for preference in Self.switches {
            #expect(first.object(forKey: preference.key) == nil)
        }
        #expect(first.object(forKey: Preferences.pieceSymbols.key) == nil)
        #expect(first.object(forKey: Preferences.notationStyle.key) == nil)
    }

    @Test("A switch stores a genuine Bool, and reads back as one")
    func aSwitchStoresABool() throws {
        let defaults = try ScratchDefaults.make()
        defer { ScratchDefaults.clear() }

        for preference in Self.switches {
            preference.set(false, in: defaults)
            // A Bool and not the string or the number that would also read as
            // false: anything asking `object(forKey:)` — a later consumer, a
            // preference inspector, another platform's reader — must be answered
            // with a Bool.
            #expect(defaults.object(forKey: preference.key) as? Bool == false,
                    "\(preference.key) should hold a Bool")
            #expect(!preference.value(in: defaults))

            preference.set(true, in: defaults)
            #expect(defaults.object(forKey: preference.key) as? Bool == true)
            #expect(preference.value(in: defaults))
        }
    }

    /// The argument domain is how a UI test names a preference state without
    /// writing anybody's real preferences, and it parses `-sound.enabled 0` into
    /// the *string* `"0"`. A reader that cast to `Bool` would quietly answer the
    /// default instead — the test would pass against the state it thought it had
    /// replaced — so the reader tolerates what that domain actually delivers.
    @Test("A preference named the way a launch argument names it is still honoured")
    func aStringFromTheArgumentDomainIsRead() throws {
        let defaults = try ScratchDefaults.make()
        defer { ScratchDefaults.clear() }

        let named: [(String, Bool)] = [("0", false), ("1", true),
                                       ("NO", false), ("YES", true),
                                       ("no", false), ("yes", true),
                                       ("false", false), ("true", true),
                                       ("False", false), ("True", true)]
        for (written, expected) in named {
            defaults.set(written, forKey: Preferences.haptics.key)
            #expect(Preferences.haptics.value(in: defaults) == expected,
                    "\(written) should read as \(expected)")
        }
    }

    /// A stored value that names no Bool is a preference nobody set — a
    /// hand-edited file, another frontend's mistake, a key colliding with
    /// something that is not this preference at all. `bool(forKey:)` answers
    /// *false* for every one of them, and false is the dangerous direction: on
    /// `deleteConfirmation.enabled` it deletes a game without asking. So the
    /// unreadable ones answer the accepted default, which is the same choice
    /// `Choice` makes about an unrecognised name.
    @Test("A stored value that names no Bool is the accepted default, never false")
    func anUnreadableFlagIsTheDefaultRatherThanFalse() throws {
        let defaults = try ScratchDefaults.make()
        defer { ScratchDefaults.clear() }

        // Every one of these reads as false through `bool(forKey:)`, "on"
        // included — which is why the reader does not ask it.
        let unreadable: [Any] = [Data([0x01]), "on", "off", "hello", "",
                                 ["1"], ["a": 1], Date(timeIntervalSince1970: 0)]
        for preference in Self.switches {
            for stored in unreadable {
                defaults.set(stored, forKey: preference.key)
                #expect(defaults.bool(forKey: preference.key) == false,
                        "the premise: \(stored) reads false through bool(forKey:)")
                #expect(preference.value(in: defaults) == preference.whenAbsent,
                        "\(preference.key) holding \(stored) should read as its default")
            }
            // A number naming neither 0 nor 1 is unreadable in the same way,
            // though it is the one case `bool(forKey:)` answers *true* to: the
            // reader honours what a value says, not whether it is non-zero.
            defaults.set(7, forKey: preference.key)
            #expect(preference.value(in: defaults) == preference.whenAbsent,
                    "\(preference.key) holding 7 should read as its default")
            // And the readable ones still are, in the same domain, so this is a
            // claim about the value rather than about the store.
            defaults.set("0", forKey: preference.key)
            #expect(!preference.value(in: defaults), "a named false is still false")
            preference.set(false, in: defaults)
            #expect(!preference.value(in: defaults), "and a genuine false is too")
            defaults.removeObject(forKey: preference.key)
            #expect(preference.value(in: defaults) == preference.whenAbsent)
        }
    }

    @Test("A 0 or 1 stored as a number is honoured, since it names the same answer")
    func aNumberThatNamesABoolIsRead() throws {
        let defaults = try ScratchDefaults.make()
        defer { ScratchDefaults.clear() }

        defaults.set(0, forKey: Preferences.sound.key)
        #expect(!Preferences.sound.value(in: defaults))
        defaults.set(1, forKey: Preferences.sound.key)
        #expect(Preferences.sound.value(in: defaults))
    }

    @Test("A choice round-trips as its name, and a string naming nothing is the default")
    func aChoiceRoundTrips() throws {
        let defaults = try ScratchDefaults.make()
        defer { ScratchDefaults.clear() }

        Preferences.pieceSymbols.set("icons", in: defaults)
        #expect(defaults.string(forKey: "pieces.symbols") == "icons",
                "the name is stored as itself, which is what another track reads")
        #expect(Preferences.pieceSymbols.value(in: defaults) == "icons")

        Preferences.notationStyle.set("wxf", in: defaults)
        #expect(defaults.string(forKey: "notation.style") == "wxf")
        #expect(Preferences.notationStyle.value(in: defaults) == "wxf")

        // A preference file is editable by hand and a key is shared with other
        // frontends, so an unrecognised value is the default rather than a
        // failure: the board still has to draw.
        defaults.set("pictograms", forKey: "pieces.symbols")
        #expect(Preferences.pieceSymbols.value(in: defaults) == "hanzi")
        defaults.set("", forKey: "notation.style")
        #expect(Preferences.notationStyle.value(in: defaults) == "traditional")
        defaults.set(7, forKey: "notation.style")
        #expect(Preferences.notationStyle.value(in: defaults) == "traditional",
                "and a value that is not even a string is the default too")
    }

    /// What this pins, exactly: a launch that names no suite reads and writes the
    /// standard database, where the player's own preferences live. The unit host
    /// is launched without arguments, so that is the whole of the claim — it says
    /// nothing about what a *release* build does with the argument, and would pass
    /// unchanged if the seam's `#if DEBUG` were deleted.
    ///
    /// Release ignoring the argument is true by construction rather than by test:
    /// `DebugLaunch` — the only thing that reads a launch argument anywhere in the
    /// app — is itself entirely inside `#if DEBUG`, so a release build carries no
    /// code that can read one.
    @Test("A launch that names no suite keeps its preferences in the standard database")
    func withoutTheArgumentThePreferencesAreTheStandardOnes() {
        #expect(Preferences.defaults === UserDefaults.standard)
    }
}
