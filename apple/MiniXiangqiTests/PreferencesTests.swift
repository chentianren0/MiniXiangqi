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

        // The stored strings, which are as much of the contract as the keys are:
        // another track reads these raw values without ever seeing this enum.
        #expect(Preferences.PieceSymbols.allCases.map(\.rawValue) == ["hanzi", "icons"])
        #expect(Preferences.NotationStyle.allCases.map(\.rawValue) == ["traditional", "wxf"])
    }

    @Test("An absent key is the accepted default, which is the state of a first launch")
    func absenceMeansTheDefault() throws {
        let first = try ScratchDefaults.make()
        defer { ScratchDefaults.clear() }

        #expect(Preferences.sound.value(in: first), "sound on")
        #expect(Preferences.haptics.value(in: first), "haptics on")
        #expect(Preferences.deleteConfirmation.value(in: first), "and it asks before deleting")
        #expect(Preferences.pieceSymbols.value(in: first) == .hanzi)
        #expect(Preferences.notationStyle.value(in: first) == .traditional)

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

        for (written, expected) in [("0", false), ("1", true), ("NO", false), ("YES", true)] {
            defaults.set(written, forKey: Preferences.haptics.key)
            #expect(Preferences.haptics.value(in: defaults) == expected,
                    "\(written) should read as \(expected)")
        }
    }

    @Test("A choice round-trips as its raw string, and a string naming no case is the default")
    func aChoiceRoundTrips() throws {
        let defaults = try ScratchDefaults.make()
        defer { ScratchDefaults.clear() }

        Preferences.pieceSymbols.set(.icons, in: defaults)
        #expect(defaults.string(forKey: "pieces.symbols") == "icons")
        #expect(Preferences.pieceSymbols.value(in: defaults) == .icons)

        Preferences.notationStyle.set(.wxf, in: defaults)
        #expect(defaults.string(forKey: "notation.style") == "wxf")
        #expect(Preferences.notationStyle.value(in: defaults) == .wxf)

        // A preference file is editable by hand and a key is shared with other
        // frontends, so an unrecognised value is the default rather than a
        // failure: the board still has to draw.
        defaults.set("pictograms", forKey: "pieces.symbols")
        #expect(Preferences.pieceSymbols.value(in: defaults) == .hanzi)
        defaults.set("", forKey: "notation.style")
        #expect(Preferences.notationStyle.value(in: defaults) == .traditional)
    }

    @Test("The app keeps its preferences in the standard database")
    func theLivePreferencesAreTheStandardOnes() {
        // The scratch-suite seam is a debug launch argument and nothing else: a
        // run that names no suite reads and writes where the player's own
        // preferences live, which is the only behaviour a release build has.
        #expect(Preferences.defaults === UserDefaults.standard)
    }
}
