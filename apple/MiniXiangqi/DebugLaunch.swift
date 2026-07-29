// The launch arguments debug builds take, in one place.
//
// Every one of them is a test affordance, never product behaviour: a UI test
// launches the app with the state it needs named on the command line, because
// the alternative is a test that clicks its way there and a screenshot that
// cannot say what it shows. Release builds compile none of this.

#if DEBUG
import Foundation

enum DebugLaunch {
    /// The value following `flag`, if both are present.
    static func argument(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag),
              arguments.index(after: index) < arguments.endIndex
        else { return nil }
        return arguments[arguments.index(after: index)]
    }

    /// Whether `flag` was given at all.
    static func contains(_ flag: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains(flag)
    }
}
#endif
