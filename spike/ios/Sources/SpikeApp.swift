import SwiftUI
import CommuneRenderer

@main
struct SpikeApp: App {
    // Dev Mac IP serving the platform repo over `tools/dev-server.py`.
    // Falls back to bundled JSONs when unreachable.
    private let devServerURL = URL(string: "http://192.168.129.8:8765")

    init() {
        // Configure both Firebase projects up front. Each tenant's `app.json`
        // declares which one it uses via the `firebase` field.
        CommuneFirebase.configure(["spike-1", "spike-2"])
    }

    var body: some Scene {
        WindowGroup {
            CommuneShell(baseURL: devServerURL)
        }
    }
}
