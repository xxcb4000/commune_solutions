import Foundation

// Async preload of tenant config + module manifests + screens + data.
// Tries HTTP first when `baseURL` is set, then falls back to bundled copies.
// Populates `PlatformAssets` so the rest of the rendering stack can stay sync.
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
        guard let tenantData = await fetchOrFallback(tenantPath, baseURL: baseURL) else {
            state = .failed("tenant \(tenant) introuvable")
            return
        }
        PlatformAssets.shared.put(tenantPath, tenantData)

        guard let tenantConfig = try? JSONDecoder().decode(DSLScreen.self, from: tenantData) else {
            state = .failed("tenant \(tenant) JSON invalide")
            return
        }

        for ref in tenantConfig.modules ?? [] {
            await loadModule(ref, baseURL: baseURL)
        }

        ModuleRegistry.shared.loadModules(tenantConfig.modules ?? [])
        state = .ready
    }

    private func loadModule(_ ref: DSLModuleRef, baseURL: URL?) async {
        let manifestPath = ScreenLoader.manifestPath(moduleId: ref.id)
        guard let manifestData = await fetchOrFallback(manifestPath, baseURL: baseURL) else {
            return
        }
        PlatformAssets.shared.put(manifestPath, manifestData)

        guard let manifest = try? JSONDecoder().decode(Manifest.self, from: manifestData) else {
            return
        }

        for (_, relPath) in manifest.screens {
            let path = ScreenLoader.modulePath("\(ref.id)/\(relPath)")
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
            let path = ScreenLoader.modulePath("\(ref.id)/\(relPath)")
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
}
