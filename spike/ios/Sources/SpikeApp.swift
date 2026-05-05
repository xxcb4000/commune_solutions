import SwiftUI
import CommuneRenderer

@main
struct SpikeApp: App {
    // Dev Mac IP serving the platform repo over `tools/dev-server.py`.
    // Falls back to bundled JSONs when unreachable.
    private let devServerURL = URL(string: "http://192.168.129.8:8765")

    init() {
        // Multi-tenant dev mode bundles both Firebase projects ; each
        // tenant's `app.json` declares which one it uses via `firebase`.
        // Single-commune builds inject `CommuneFirebaseProjects` in
        // Info.plist via xcodegen env substitution → only that one
        // project is loaded.
        //
        // Si `FirebaseEmulatorHost` est set dans Info.plist (build dev avec
        // `tools/dev-emulators.sh`), Auth + Firestore parlent à l'emulator
        // local au lieu du vrai Firebase.
        let projects = Self.firebaseProjects
        CommuneFirebase.configure(projects, emulatorHost: Self.emulatorHost)
    }

    var body: some Scene {
        WindowGroup {
            // When `CommuneTenantID` is baked in Info.plist (single-commune
            // build for a specific commune), pass it to the shell so the
            // picker is skipped and the app boots straight on that tenant.
            // When absent (dev / multi-tenant), shell falls back to picker.
            CommuneShell(tenant: Self.bakedTenant, baseURL: devServerURL)
        }
    }

    /// Tenant ID baked at build time, or `nil` to fall back to picker mode.
    private static var bakedTenant: String? {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CommuneTenantID") as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    /// Firebase project IDs to configure. Single-commune builds set this to
    /// just the one project ; the multi-tenant dev build keeps both for
    /// the picker scenario.
    private static var firebaseProjects: [String] {
        let raw = Bundle.main.object(forInfoDictionaryKey: "CommuneFirebaseProjects") as? String
        let parsed = (raw ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return parsed.isEmpty ? ["spike-1", "spike-2"] : parsed
    }

    /// Host des Firebase emulators locaux. Set ⇒ Auth + Firestore SDK
    /// pointent sur les emulators (ports 9099 + 8080). Vide / non set ⇒
    /// vrai Firebase. Géré via xcodegen env var au build.
    private static var emulatorHost: String? {
        let raw = Bundle.main.object(forInfoDictionaryKey: "FirebaseEmulatorHost") as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }
}
