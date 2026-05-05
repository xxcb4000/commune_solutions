import Foundation
import FirebaseCore

// Async preload of tenant config + module manifests + screens + data.
// Tries HTTP first when `baseURL` is set, then falls back to bundled copies.
// Populates `PlatformAssets` so the rest of the rendering stack can stay sync.
//
// Phase 11.3 : la liste des modules activés et la nav (`view`) viennent de
// Firestore (`_config/modules`) plutôt que du JSON bundle. Si Firestore
// répond, on patch le JSON tenant en mémoire avant de l'exposer à
// ScreenLoader. Sinon : fallback transparent sur le JSON (mode bootstrap).
@MainActor
final class AssetPreloader: ObservableObject {

    enum State: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    @Published var state: State = .idle

    func start(tenant: String, baseURL: URL?) {
        guard state == .idle else { return }
        state = .loading
        Task { @MainActor in
            await load(tenant: tenant, baseURL: baseURL)
        }
    }

    private func load(tenant: String, baseURL: URL?) async {
        let tenantPath = ScreenLoader.tenantPath(tenant)
        guard var tenantData = await fetchOrFallback(tenantPath, baseURL: baseURL) else {
            state = .failed("tenant \(tenant) introuvable")
            return
        }

        // First decode pass — extract firebase app name + functionsBaseURL.
        guard let bootstrap = try? JSONDecoder().decode(DSLScreen.self, from: tenantData) else {
            state = .failed("tenant \(tenant) JSON invalide")
            return
        }
        TenantContext.shared.functionsBaseURL = bootstrap.functionsBaseURL.flatMap { URL(string: $0) }

        // Try Firestore override of runtime config (modules + view).
        if let firebaseName = bootstrap.firebase,
           let projectId = FirebaseApp.app(name: firebaseName)?.options.projectID,
           let runtime = await Self.fetchFirestoreRuntimeConfig(projectId: projectId),
           let patched = Self.applyRuntimeConfig(runtime, to: tenantData) {
            tenantData = patched
            print("AssetPreloader: tenant runtime config from Firestore (\(projectId))")
        } else {
            print("AssetPreloader: tenant runtime config from bundle (Firestore unavailable)")
        }

        PlatformAssets.shared.put(tenantPath, tenantData)

        // Re-decode in case we patched.
        guard let tenantConfig = try? JSONDecoder().decode(DSLScreen.self, from: tenantData) else {
            state = .failed("tenant \(tenant) JSON invalide après merge")
            return
        }

        for ref in tenantConfig.modules ?? [] {
            await loadModule(ref, baseURL: baseURL)
        }

        ModuleRegistry.shared.loadModules(tenantConfig.modules ?? [])
        state = .ready
    }

    private func loadModule(_ ref: DSLModuleRef, baseURL: URL?) async {
        // Try chaque root (modules-official prioritaire, puis modules-community)
        // jusqu'à trouver le manifest. Le root résolu est ensuite réutilisé
        // pour fetcher screens + data au bon endroit.
        var resolvedRoot: String?
        var manifestData: Data?
        for root in ScreenLoader.moduleRoots {
            let path = "\(root)/\(ref.id)/manifest.json"
            if let data = await fetchOrFallback(path, baseURL: baseURL) {
                PlatformAssets.shared.put(path, data)
                resolvedRoot = root
                manifestData = data
                break
            }
        }
        guard let resolvedRoot, let manifestData,
              let manifest = try? JSONDecoder().decode(Manifest.self, from: manifestData) else {
            return
        }

        for (_, relPath) in manifest.screens {
            let path = "\(resolvedRoot)/\(ref.id)/\(relPath)"
            guard let data = await fetchOrFallback(path, baseURL: baseURL) else { continue }
            PlatformAssets.shared.put(path, data)

            // Walk the screen's data declarations and eagerly fetch any
            // `cf:<endpoint>` source so the renderer can stay synchronous.
            if let dsl = try? JSONDecoder().decode(DSLScreen.self, from: data) {
                for (_, source) in dsl.data ?? [:] {
                    if source.hasPrefix("cf:") {
                        let endpoint = String(source.dropFirst(3))
                        if let cfData = await fetchCF(moduleId: ref.id, endpoint: endpoint, baseURL: baseURL) {
                            let cacheKey = Self.cfCacheKey(moduleId: ref.id, endpoint: endpoint)
                            PlatformAssets.shared.put(cacheKey, cfData)
                        }
                    }
                }
            }
        }
        for (_, relPath) in manifest.data ?? [:] {
            let path = "\(resolvedRoot)/\(ref.id)/\(relPath)"
            if let data = await fetchOrFallback(path, baseURL: baseURL) {
                PlatformAssets.shared.put(path, data)
            }
        }
    }

    static func cfCacheKey(moduleId: String, endpoint: String) -> String {
        "cf:\(moduleId)/\(endpoint)"
    }

    private func fetchCF(moduleId: String, endpoint: String, baseURL: URL?) async -> Data? {
        guard let baseURL else { return nil }
        let url = baseURL.appendingPathComponent("cf/\(moduleId)/\(endpoint)")
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                print("AssetPreloader: CF \(moduleId)/\(endpoint)")
                return data
            }
        } catch {
            print("AssetPreloader: CF failed \(moduleId)/\(endpoint) — \(error.localizedDescription)")
        }
        return nil
    }

    private func fetchOrFallback(_ path: String, baseURL: URL?) async -> Data? {
        if let baseURL {
            let url = baseURL.appendingPathComponent(path)
            // Bypass URLSession's local disk cache so the spike picks up
            // dev-server edits between launches. Production will rely on
            // proper Cache-Control headers from the platform CDN.
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    print("AssetPreloader: HTTP \(path)")
                    return data
                }
            } catch {
                print("AssetPreloader: HTTP failed \(path) — \(error.localizedDescription)")
            }
        }
        if let data = ScreenLoader.readBundle(path) {
            print("AssetPreloader: bundle \(path)")
            return data
        }
        print("AssetPreloader: missing \(path)")
        return nil
    }

    // MARK: - Firestore runtime config

    // GET _config/modules via REST. Public read (Firestore rules), pas d'auth
    // requis : utile car le preloader tourne avant le login. Format de
    // réponse : Firestore typed JSON (stringValue, arrayValue, mapValue) que
    // `unwrapFirestoreValue` reconvertit en JSON plain.
    private static func fetchFirestoreRuntimeConfig(projectId: String) async -> [String: Any]? {
        let urlString = "https://firestore.googleapis.com/v1/projects/\(projectId)/databases/(default)/documents/_config/modules"
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                print("AssetPreloader: Firestore _config/modules HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return nil
            }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let fields = json?["fields"] as? [String: Any] else { return nil }
            var out: [String: Any] = [:]
            for (k, v) in fields {
                if let unwrapped = unwrapFirestoreValue(v) {
                    out[k] = unwrapped
                }
            }
            return out
        } catch {
            print("AssetPreloader: Firestore _config/modules fetch error — \(error.localizedDescription)")
            return nil
        }
    }

    private static func unwrapFirestoreValue(_ v: Any) -> Any? {
        guard let dict = v as? [String: Any] else { return nil }
        if let s = dict["stringValue"] as? String { return s }
        if let b = dict["booleanValue"] as? Bool { return b }
        if let n = dict["integerValue"] as? String { return Int(n) ?? n }
        if let d = dict["doubleValue"] as? Double { return d }
        if dict["nullValue"] != nil { return NSNull() }
        if let arr = dict["arrayValue"] as? [String: Any] {
            let values = arr["values"] as? [Any] ?? []
            return values.compactMap(unwrapFirestoreValue)
        }
        if let map = dict["mapValue"] as? [String: Any] {
            let fields = map["fields"] as? [String: Any] ?? [:]
            var out: [String: Any] = [:]
            for (k, v) in fields {
                if let unwrapped = unwrapFirestoreValue(v) {
                    out[k] = unwrapped
                }
            }
            return out
        }
        return nil
    }

    // Patche le JSON tenant : remplace les clés `modules` et `view` par les
    // valeurs venues de Firestore. Garde les autres clés (tenant, firebase,
    // functionsBaseURL) intactes — elles restent du bootstrap.
    private static func applyRuntimeConfig(_ runtime: [String: Any], to tenantData: Data) -> Data? {
        guard var tenantJson = try? JSONSerialization.jsonObject(with: tenantData) as? [String: Any] else {
            return nil
        }
        if let modules = runtime["modules"] {
            tenantJson["modules"] = modules
        }
        if let view = runtime["view"] {
            tenantJson["view"] = view
        }
        return try? JSONSerialization.data(withJSONObject: tenantJson)
    }
}
