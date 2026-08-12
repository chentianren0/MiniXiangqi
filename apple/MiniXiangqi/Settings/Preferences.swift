// The preferences the app keeps, and the one place each of them is read.
//
// docs/product.md, "Product navigation": Settings holds the persistent user
// preferences, it stores no game data, and they live in each platform's own
// preference system rather than in the shared core. Issue #64's Stage 5 design
// fixes the rest of that contract — the key each preference is stored under, its
// type, and what its absence means — because the screen that writes these keys
// and the renderings that read them are built as separate pieces of work. The
// key is the interface between them, so it is written down once, here.
//
// | Key | Type | Absent means |
// |---|---|---|
// | `sound.enabled` | Bool | on |
// | `haptics.enabled` | Bool | on |
// | `deleteConfirmation.enabled` | Bool | on |
// | `placementConfirmation.enabled` | Bool | off |
// | `pieces.symbols` | `hanzi` \| `icons` | `hanzi` |
// | `notation.style` | `traditional` \| `wxf` | the interface language's own |
// | `defaults.firstMover` | `human-first` \| `ai-first` \| `random` | `human-first` |
// | `defaults.aiLevel` | `fast` \| `standard` \| `deep` | `standard` |
//
// **Every one is read at the moment of use** and nothing is cached at launch, so
// a switch takes effect on the next event rather than on the next run. That was
// already the rule the sound gate was written to; all five share it now, and
// share one reader, so that "absent means the accepted default" is stated in one
// place instead of once per consumer.
//
// One default is no longer a constant: `notation.style`'s is the interface
// language's — WXF in English, the traditional rendering in Chinese — by the
// owner's decision of 2026-07-30. That is why a `Choice`'s default is a closure
// below rather than a string. Nothing about the *storage* changed: the resolved
// answer is what an absent key reads as, and the moment somebody chooses in
// Settings a name is written and the language stops being asked.
//
// What a preference *means* is not this file's business. The two choices are
// stored and read as the names in the table above, and the rendering that reads
// one maps it to its own vocabulary: the notation's own type belongs beside the
// notation, not beside the preference that selects it.

import Foundation

enum Preferences {

    // MARK: - The five

    /// Whether the board is heard: the gate in front of `Feedback`'s heard half.
    static let sound = Flag(key: "sound.enabled", whenAbsent: true)

    /// Whether the board is felt: the gate in front of `Feedback`'s felt half.
    /// Offered on macOS, where the hardware question belongs to the trackpad and
    /// the system performer already answers it per machine, per
    /// docs/interaction-design.md § Sound and haptics.
    static let haptics = Flag(key: "haptics.enabled", whenAbsent: true)

    /// Whether deleting a History record asks first. Off means a deletion is
    /// immediate — and permanent, which is what the accepted footer beside the
    /// switch says out loud.
    static let deleteConfirmation = Flag(key: "deleteConfirmation.enabled",
                                         whenAbsent: true)

    /// Whether placing a stone asks first. **Off by default**, which is the
    /// accepted decision: a tap places the stone, and the pending stone is the
    /// flow a player turns on. On means a tap marks the point instead — see
    /// `Game.placementEffect(ofTapAt:…)`, which owns the grammar — and the mark
    /// is committed by tapping it again.
    ///
    /// It is the delete confirmation's shape and not its default, because the
    /// two protect different things: a deletion cannot be undone, and a stone
    /// placed by mistake is one Undo away wherever it is placed.
    static let placementConfirmation = Flag(key: "placementConfirmation.enabled",
                                            whenAbsent: false)

    /// What the discs carry — the accepted symbol sets of
    /// docs/interaction-design.md § Piece symbols: `hanzi`, the default, or
    /// `icons`. Independent of how a move is written: a learner may want icons on
    /// a board whose move list they are learning to read.
    static let pieceSymbols = Choice(key: "pieces.symbols",
                                     whenAbsent: "hanzi",
                                     names: ["hanzi", "icons"])

    /// How a move is written, in the move list and in the numeral strips that
    /// exist to map it to the board: `traditional` or `wxf`, and where nobody
    /// has chosen, whichever one the interface language reads — see
    /// `NotationStyle.resolved(forInterfaceLanguage:)`, which owns that rule and
    /// the reasoning for it.
    static let notationStyle = Choice(key: "notation.style",
                                      whenAbsent: NotationStyle.resolvedForInterfaceLanguage.rawValue,
                                      names: ["traditional", "wxf"])

    /// Which side a new human-versus-AI game opens on — the value the pre-start
    /// draft is initialized from, never the created game's own. The names are
    /// docs/game-data.md's serialized first-mover vocabulary, so the preference,
    /// the frozen configuration and the archive all say the same three words.
    static let defaultFirstMover = Choice(key: "defaults.firstMover",
                                          whenAbsent: "human-first",
                                          names: ["human-first", "ai-first", "random"])

    /// How long a new human-versus-AI game's opponent thinks. 标准 on a new
    /// installation, per the accepted profiles.
    static let defaultAiLevel = Choice(key: "defaults.aiLevel",
                                       whenAbsent: "standard",
                                       names: ["fast", "standard", "deep"])

    /// The two above as the vocabulary the setup page speaks. A stored name
    /// nothing recognises reads as the accepted default, exactly as `Choice`
    /// says it does — a preference file is editable by hand and read by more
    /// than one frontend, and the page still has to open.
    static func defaultFirstMover(in defaults: UserDefaults = Preferences.defaults)
        -> FirstMoverChoice {
        FirstMoverChoice(name: defaultFirstMover.value(in: defaults)) ?? .humanFirst
    }

    static func defaultAiLevel(in defaults: UserDefaults = Preferences.defaults)
        -> AiLevel {
        AiLevel(name: defaultAiLevel.value(in: defaults)) ?? .standard
    }

    // MARK: - How one is read and written

    /// A preference that is on or off: a switch in Settings, and one of the
    /// accepted defaults until somebody moves it.
    struct Flag {
        let key: String
        /// What an absent key means — the state of every first launch.
        let whenAbsent: Bool

        /// Read at the moment of use, never cached.
        ///
        /// Two kinds of stored value are honoured, and everything else is the
        /// accepted default:
        ///
        /// - **A Bool**, which is what the switch writes — and a 0 or 1 number,
        ///   which is the same answer written by something that had no Bool to
        ///   write, another frontend or a hand-edited file.
        /// - **One of the strings that names a Bool** — `1`, `0`, `YES`, `NO`,
        ///   `true`, `false`, in any case. A debug launch argument is how a UI
        ///   test names a preference state without writing anybody's real
        ///   preferences, and the argument domain delivers `-haptics.enabled 0`
        ///   as the *string* `"0"`: a reader that only cast to `Bool` would
        ///   silently answer the default, and the test would be asserting against
        ///   the state it thought it had replaced.
        ///
        /// **Anything else answers `whenAbsent`, and that direction matters.** A
        /// stored value of the wrong type is a preference nobody set — a
        /// hand-edited file, another frontend's mistake, a key colliding with
        /// something that is not this. `bool(forKey:)` would answer *false* for
        /// almost all of it — `on`, `[1]`, a date, an empty string — and *true*
        /// for any non-zero number, so it is not asked: false is the dangerous
        /// answer here, because on `deleteConfirmation.enabled` it deletes a game
        /// without asking, and true is not an answer anybody gave either. So an
        /// unreadable preference reads as the accepted default, exactly as an
        /// unrecognised name does in `Choice` below, and for the same reason: the
        /// app still has to behave, and the default is what it behaves as.
        func value(in defaults: UserDefaults = Preferences.defaults) -> Bool {
            switch defaults.object(forKey: key) {
            case let flag as Bool: flag
            case let text as String: Self.namedFlags[text.lowercased()] ?? whenAbsent
            default: whenAbsent
            }
        }

        /// The strings that name a Bool, lowercased. `as? Bool` already covers a
        /// genuine Bool and a 0-or-1 number, which is why neither is here.
        private static let namedFlags = ["1": true, "0": false,
                                         "yes": true, "no": false,
                                         "true": true, "false": false]

        /// Written as a Bool and never as a string or a number, so that anything
        /// asking `object(forKey:)` is answered with a Bool.
        func set(_ value: Bool, in defaults: UserDefaults = Preferences.defaults) {
            defaults.set(value, forKey: key)
        }
    }

    /// A preference chosen among a fixed set of names, stored as the name itself.
    /// A name rather than an index, because an index is a position in a list that
    /// a later design may reorder and a name is not.
    ///
    /// **The names are plain strings, and no type is declared for them here.**
    /// Each of these is read by a different piece of work — the disc rendering
    /// reads `pieces.symbols`, the move list and the numeral strips read
    /// `notation.style` — and each of those has its own type for what it draws. A
    /// type declared here as well would be a second vocabulary for the same
    /// choice, to be kept in step by hand; the stored string is the interface, as
    /// issue #64's key table says it is.
    struct Choice {
        let key: String
        /// What an absent key means — the state of every first launch — and what
        /// an unrecognised one means too.
        ///
        /// **Asked rather than stored**, because one of these defaults is not a
        /// constant: `notation.style`'s is the interface language's answer, and a
        /// default captured when this table was built would be a different kind
        /// of thing from a default read at the moment of use, which is what every
        /// other value here is. The other three choices pass a literal and read
        /// exactly as they did.
        let whenAbsent: () -> String
        /// Every name this preference accepts.
        let names: [String]

        init(key: String,
             whenAbsent: @autoclosure @escaping () -> String,
             names: [String]) {
            self.key = key
            self.whenAbsent = whenAbsent
            self.names = names
        }

        /// Read at the moment of use, like every other preference here. A stored
        /// string that names nothing is the default rather than a failure: a
        /// preference file can be edited by hand and is read by more than one
        /// frontend, and the board still has to draw.
        func value(in defaults: UserDefaults = Preferences.defaults) -> String {
            guard let stored = defaults.string(forKey: key), names.contains(stored)
            else { return whenAbsent() }
            return stored
        }

        /// Writes one of `names`. Anything else is a mistake in the caller rather
        /// than a state to store, and it is stored anyway, because a preference
        /// this screen writes and cannot read back is worse than one a test can
        /// see is wrong.
        func set(_ value: String, in defaults: UserDefaults = Preferences.defaults) {
            defaults.set(value, forKey: key)
        }
    }

    // MARK: - Where they are kept

    /// The defaults database every read and write above goes through.
    ///
    /// The standard one, except that a debug launch may name a scratch suite with
    /// `-mxq-defaults-suite <name>`: a UI test that *clicks* a switch writes a
    /// real preference, and the player's own preferences are no more a test
    /// fixture than the player's own games are — the same reason
    /// `-mxq-store-name` exists for the store. A named suite is searched ahead of
    /// the app's own domain and behind the argument domain, so a launch argument
    /// still names a state to read and a click still persists one to re-read.
    ///
    /// Resolved once, because a launch argument cannot change while the app runs;
    /// what is never cached is the *value* of a preference, which is a different
    /// thing from the database it is kept in.
    static let defaults: UserDefaults = {
        #if DEBUG
        if let name = DebugLaunch.argument(after: "-mxq-defaults-suite"),
           let suite = UserDefaults(suiteName: name) {
            return suite
        }
        #endif
        return .standard
    }()
}
