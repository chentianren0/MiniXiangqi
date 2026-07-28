import SwiftUI

struct ContentView: View {
    var body: some View {
        switch Core.shared {
        case .success(let core):
            PlayScreen(core: core)
        case .failure(let error):
            // A core that will not start is a packaging failure, and saying so
            // plainly beats an empty board that silently does nothing.
            ContentUnavailableView("The core did not start", systemImage: "exclamationmark.triangle",
                                   description: Text(error.description).monospaced())
        }
    }
}
