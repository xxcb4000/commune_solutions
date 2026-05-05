import Foundation
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import SwiftUI
import Combine

// MARK: - Multi-project Firebase setup

/// Public helper for the consuming app to call once at launch. For each name,
/// loads `firebase/<name>/GoogleService-Info.plist` from the main bundle and
/// configures a named `FirebaseApp`. Tenant configs reference the name via
/// their `firebase` field; the renderer looks up the matching `FirebaseApp`
/// at runtime.
///
/// Si `emulatorHost` est fourni (ex: "127.0.0.1" ou IP du Mac dev), Auth +
/// Firestore sont routés vers les emulators locaux (ports standards Firebase
/// 9099 et 8080). Permet aux contributeurs de développer sans projet Firebase
/// réel — `tools/dev-emulators.sh` lance les emulators côté Mac.
public enum CommuneFirebase {
    public static func configure(_ names: [String], emulatorHost: String? = nil) {
        for name in names {
            if FirebaseApp.app(name: name) != nil { continue }
            let path = "\(Bundle.main.bundlePath)/firebase/\(name)/GoogleService-Info.plist"
            guard FileManager.default.fileExists(atPath: path),
                  let opts = FirebaseOptions(contentsOfFile: path) else {
                print("CommuneFirebase: missing config for \(name)")
                continue
            }
            FirebaseApp.configure(name: name, options: opts)
            if let host = emulatorHost, !host.isEmpty,
               let app = FirebaseApp.app(name: name) {
                Auth.auth(app: app).useEmulator(withHost: host, port: 9099)
                let settings = Firestore.firestore(app: app).settings
                settings.host = "\(host):8080"
                settings.isSSLEnabled = false
                settings.cacheSettings = MemoryCacheSettings()
                Firestore.firestore(app: app).settings = settings
                print("CommuneFirebase: configured \(name) with emulator at \(host)")
            } else {
                print("CommuneFirebase: configured \(name)")
            }
        }
    }

    static func signOutAll() {
        for app in FirebaseApp.allApps?.values ?? [:].values {
            try? Auth.auth(app: app).signOut()
        }
    }
}

// MARK: - Auth state observer

@MainActor
final class AuthObserver: ObservableObject {
    @Published var user: User?
    private var handle: AuthStateDidChangeListenerHandle?
    private weak var app: FirebaseApp?

    init(app: FirebaseApp) {
        self.app = app
        self.user = Auth.auth(app: app).currentUser
        self.handle = Auth.auth(app: app).addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.user = user }
        }
    }

    deinit {
        if let handle, let app {
            Auth.auth(app: app).removeStateDidChangeListener(handle)
        }
    }
}

// MARK: - Login form

struct LoginForm: View {
    let firebaseApp: FirebaseApp
    let tenantTitle: String
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var error: String?
    @State private var loading: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Connexion")
                    .font(.title.weight(.bold))
                Text(tenantTitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 16)

            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()

            SecureField("Mot de passe", text: $password)
                .textFieldStyle(.roundedBorder)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Task { await login() }
            } label: {
                Group {
                    if loading {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Se connecter").frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(loading || email.isEmpty || password.isEmpty)

            Button("Changer de commune") {
                UserDefaults.standard.removeObject(forKey: "communeShell.tenant")
            }
            .font(.callout)
            .foregroundStyle(.tint)
            .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @MainActor
    private func login() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            _ = try await Auth.auth(app: firebaseApp).signIn(withEmail: email, password: password)
        } catch let e as NSError {
            // Firebase Auth error codes are in e.code; the message in localizedDescription is OK.
            error = e.localizedDescription
        }
    }
}
