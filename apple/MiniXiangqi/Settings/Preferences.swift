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
// | `pieces.symbols` | `hanzi` \| `icons` | `hanzi` |
// | `notation.style` | `traditional` \| `wxf` | `traditional` |
//
// **Every one is read at the moment of use** and nothing is cached at launch, so
// a switch takes effect on the next event rather than on the next run. That was
// already the rule the sound gate was written to; all five share it now, and
// share one reader, so that "absent means the accepted default" is stated in one
// place instead of once per consumer.

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

    /// What the discs carry. Independent of how a move is written: a learner may
    /// want icons on a board whose move list they are learning to read.
    static let pieceSymbols = Choice(key: "pieces.symbols",
                                     whenAbsent: PieceSymbols.hanzi)

    /// How a move is written, in the move list and in the numeral strips that
    /// exist to map it to the board.
    static let notationStyle = Choice(key: "notation.style",
                                      whenAbsent: NotationStyle.traditional)

    /// The accepted symbol sets of docs/interaction-design.md § Piece symbols.
    /// The raw values are the stored contract and are not copy: what each is
    /// called on screen is a string in docs/copy.md.
    enum PieceSymbols: String, CaseIterable {
        /// 汉字 — the accepted default.
        case hanzi
        /// 图标 — a pictorial symbol per piece type.
        case icons
    }

    /// The accepted notations of docs/interaction-design.md § User-visible
    /// notation, under the same rule: raw values are stored, never shown.
    enum NotationStyle: String, CaseIterable {
        /// 中文 — traditional Chinese notation, the accepted default.
        case traditional
        /// WXF, which is identical in both interface languages.
        case wxf
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
        /// Presence is asked first and the value second, rather than casting the
        /// stored object to `Bool`. The switch writes a genuine Bool, but a debug
        /// launch argument — `-haptics.enabled 0`, which is how a UI test names a
        /// preference state without writing anybody's real preferences — arrives
        /// in the argument domain as the *string* `"0"`, which no `as? Bool` can
        /// recover: it would silently read as the default and a test would be
        /// asserting against the state it thought it had replaced.
        /// `bool(forKey:)` reads both, so the preference a test names is the
        /// preference the app honours.
        func value(in defaults: UserDefaults = Preferences.defaults) -> Bool {
            guard defaults.object(forKey: key) != nil else { return whenAbsent }
            return defaults.bool(forKey: key)
        }

        /// Written as a Bool and never as a string or a number, so that anything
        /// asking `object(forKey:)` is answered with a Bool.
        func set(_ value: Bool, in defaults: UserDefaults = Preferences.defaults) {
            defaults.set(value, forKey: key)
        }
    }

    /// A preference chosen among named cases, stored as the raw string of the one
    /// selected. A string rather than an index, because an index is a position in
    /// a list that a later design may reorder and a raw value is not.
    struct Choice<Value: RawRepresentable & CaseIterable> where Value.RawValue == String {
        let key: String
        let whenAbsent: Value

        /// Read at the moment of use, like every other preference here. A stored
        /// string naming no case is the default rather than a failure: a
        /// preference file can be edited by hand, and the board still has to draw.
        func value(in defaults: UserDefaults = Preferences.defaults) -> Value {
            guard let raw = defaults.string(forKey: key),
                  let stored = Value(rawValue: raw)
            else { return whenAbsent }
            return stored
        }

        func set(_ value: Value, in defaults: UserDefaults = Preferences.defaults) {
            defaults.set(value.rawValue, forKey: key)
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
