import Foundation

// Lexical scope of named bindings, evaluated against dotted paths.
struct DSLScope {
    private var bindings: [String: DSLValue]

    init(bindings: [String: DSLValue] = [:]) {
        self.bindings = bindings
    }

    func lookup(_ path: String) -> DSLValue? {
        let parts = path.split(separator: ".").map(String.init)
        guard let head = parts.first, let root = bindings[head] else { return nil }
        if parts.count == 1 { return root }
        return root.get(Array(parts.dropFirst()))
    }

    func adding(_ key: String, _ value: DSLValue) -> DSLScope {
        var copy = self
        copy.bindings[key] = value
        return copy
    }
}

// Templating: {{ path.to.value }} resolution against a scope.
enum Template {
    // Replace all bindings with their string forms; passthrough literal text.
    static func resolve(_ str: String, scope: DSLScope) -> String {
        var result = ""
        var rest = Substring(str)
        while let openRange = rest.range(of: "{{") {
            result.append(contentsOf: rest[..<openRange.lowerBound])
            rest = rest[openRange.upperBound...]
            guard let closeRange = rest.range(of: "}}") else {
                result.append(contentsOf: "{{")
                result.append(contentsOf: rest)
                return result
            }
            let key = rest[..<closeRange.lowerBound].trimmingCharacters(in: .whitespaces)
            rest = rest[closeRange.upperBound...]
            if let v = scope.lookup(key) {
                result.append(contentsOf: v.stringValue)
            }
        }
        result.append(contentsOf: rest)
        return result
    }

    // If the input is exactly one binding, preserve its native type. Otherwise stringify.
    static func resolveValue(_ str: String, scope: DSLScope) -> DSLValue {
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("{{") && trimmed.hasSuffix("}}") {
            let inner = String(trimmed.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
            if !inner.contains("{{") && !inner.contains("}}") {
                return scope.lookup(inner) ?? .null
            }
        }
        return .string(resolve(str, scope: scope))
    }
}

// In-memory cache populated by AssetPreloader at startup. Read by ScreenLoader
// for every JSON access. If the cache misses, ScreenLoader falls back to the
// bundle so the app still works fully offline.
final class PlatformAssets {
    static let shared = PlatformAssets()
    private var cache: [String: Data] = [:]
    private let lock = NSLock()

    private init() {}

    func put(_ path: String, _ data: Data) {
        lock.lock(); defer { lock.unlock() }
        cache[path] = data
    }

    func get(_ path: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        return cache[path]
    }
}

// Loads platform JSONs (tenant config, manifests, screens, data). Reads from
// PlatformAssets cache when possible, falls back to the consuming app's main
// bundle so the spike continues to work offline.
//
// Bundle / cache layout:
//   `tenants/<id>/app.json`
//   `modules-official/<id>/manifest.json`
//   `modules-official/<id>/<module-relative-path>` (screens, data)
//
// Bundle file lookup uses `bundlePath + URL(fileURLWithPath:)` to avoid
// percent-encoding when joining path components, and to work with folder
// references (`type: folder` in xcodegen) which `url(forResource:)` does not
// index.
enum ScreenLoader {
    static let moduleRoot = "modules-official"
    static let tenantRoot = "tenants"

    static func tenantPath(_ name: String) -> String { "\(tenantRoot)/\(name)/app.json" }
    static func manifestPath(moduleId: String) -> String { "\(moduleRoot)/\(moduleId)/manifest.json" }
    static func modulePath(_ bundlePath: String) -> String { "\(moduleRoot)/\(bundlePath)" }

    static func loadTenant(_ name: String) -> DSLScreen? {
        decodeFile(tenantPath(name))
    }

    static func loadManifest(moduleId: String) -> Manifest? {
        decodeFile(manifestPath(moduleId: moduleId))
    }

    static func loadScreen(at bundlePath: String) -> DSLScreen? {
        decodeFile(modulePath(bundlePath))
    }

    static func loadData(at bundlePath: String) -> DSLValue? {
        decodeFile(modulePath(bundlePath))
    }

    private static func decodeFile<T: Decodable>(_ path: String) -> T? {
        let data: Data
        if let cached = PlatformAssets.shared.get(path) {
            data = cached
        } else if let bundleData = readBundle(path) {
            data = bundleData
        } else {
            print("ScreenLoader: \(path) not in cache nor bundle")
            return nil
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("ScreenLoader: decode error \(path) — \(error)")
            return nil
        }
    }

    static func readBundle(_ path: String) -> Data? {
        let fullPath = "\(Bundle.main.bundlePath)/\(path)"
        return try? Data(contentsOf: URL(fileURLWithPath: fullPath))
    }
}

// Holds module manifests loaded at startup and resolves qualified screen IDs
// (e.g. "actualites:feed") to bundle paths. Singleton — manifests are
// effectively static for the lifetime of the app.
final class ModuleRegistry {
    static let shared = ModuleRegistry()
    private var manifests: [String: Manifest] = [:]

    private init() {}

    func loadModules(_ refs: [DSLModuleRef]) {
        for ref in refs {
            if let m = ScreenLoader.loadManifest(moduleId: ref.id) {
                manifests[ref.id] = m
            }
        }
    }

    func screenPath(qualified: String) -> String? {
        let parts = qualified.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let manifest = manifests[parts[0]],
              let relPath = manifest.screens[parts[1]] else { return nil }
        return "\(parts[0])/\(relPath)"
    }

    func dataPath(moduleId: String, dataName: String) -> String? {
        guard let manifest = manifests[moduleId],
              let relPath = manifest.data?[dataName] else { return nil }
        return "\(moduleId)/\(relPath)"
    }

    func qualify(_ screenRef: String, currentModule: String?) -> String {
        if screenRef.contains(":") { return screenRef }
        guard let mod = currentModule else { return screenRef }
        return "\(mod):\(screenRef)"
    }

    func module(of qualified: String) -> String? {
        let parts = qualified.split(separator: ":", maxSplits: 1).map(String.init)
        return parts.count == 2 ? parts[0] : nil
    }
}

// NavigationStack route value. Always carries a qualified screen ID
// (`<module>:<screen>`) so the destination can resolve the bundle path
// without ambient context.
struct Route: Hashable {
    let qualifiedScreen: String
    private let bindingsJSON: String

    init(qualifiedScreen: String, bindings: [String: DSLValue]) {
        self.qualifiedScreen = qualifiedScreen
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(bindings)) ?? Data()
        self.bindingsJSON = String(data: data, encoding: .utf8) ?? "{}"
    }

    var bindings: [String: DSLValue] {
        guard let data = bindingsJSON.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: DSLValue].self, from: data)) ?? [:]
    }
}
