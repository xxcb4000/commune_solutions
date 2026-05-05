import SwiftUI
import FirebaseCore
import FirebaseFirestore

// MARK: - Public entry point

/// Top-level shell.
///
/// On first launch (no tenant chosen yet), shows a native picker so the user
/// can select which commune they belong to. The choice is persisted via
/// `UserDefaults` (`@AppStorage`) and survives app restarts. After login the
/// shell hands off to `TenantHost`, which preloads the chosen tenant's
/// modules + DSL and renders the `view`.
///
/// Phase 4a: tenant picker is a hardcoded list (`spike`, `spike-2`); auth is
/// implicit (just selecting). Phase 4b will swap this for Firebase Auth.
public struct CommuneShell: View {
    @AppStorage("communeShell.tenant") private var storedTenant: String = ""
    private let tenantOverride: String?
    private let baseURL: URL?

    public init(tenant: String? = nil, baseURL: URL? = nil) {
        self.tenantOverride = tenant
        self.baseURL = baseURL
    }

    public var body: some View {
        let activeTenant = tenantOverride ?? storedTenant
        if activeTenant.isEmpty {
            TenantPicker { picked in storedTenant = picked }
        } else {
            // .id() makes SwiftUI recreate TenantHost (and its preloader)
            // whenever the active tenant changes — clean reset on logout.
            TenantHost(tenantId: activeTenant, baseURL: baseURL)
                .id(activeTenant)
                .environment(\.currentBaseURL, baseURL)
        }
    }
}

private struct TenantPicker: View {
    let onPick: (String) -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 8) {
                Text("Commune Solutions")
                    .font(.largeTitle.weight(.bold))
                Text("Sélectionnez votre commune")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                pickerCard(title: "Démo A", subtitle: "Tenant test #1", id: "spike")
                pickerCard(title: "Démo B", subtitle: "Tenant test #2", id: "spike-2")
            }
            Spacer()
            Text("Phase 4a — choix mock. Auth Firebase à venir en 4b.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pickerCard(title: String, subtitle: String, id: String) -> some View {
        Button { onPick(id) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title3.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct TenantHost: View {
    let tenantId: String
    let baseURL: URL?
    @StateObject private var preloader = AssetPreloader()

    var body: some View {
        switch preloader.state {
        case .idle, .loading:
            VStack(spacing: 16) {
                ProgressView()
                Text("Chargement des modules…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                preloader.start(tenant: tenantId, baseURL: baseURL)
            }
        case .ready:
            authGate()
        case .failed(let message):
            FallbackNotFound(message)
        }
    }

    @ViewBuilder
    private func authGate() -> some View {
        if let tenantConfig = ScreenLoader.loadTenant(tenantId),
           let firebaseName = tenantConfig.firebase,
           let firebaseApp = FirebaseApp.app(name: firebaseName) {
            AuthGate(firebaseApp: firebaseApp, tenantConfig: tenantConfig, tenantId: tenantId)
        } else {
            FallbackNotFound("tenant \(tenantId) — config Firebase manquante")
        }
    }
}

// Decides between LoginForm and tenant content based on the FirebaseAuth
// state of the tenant's Firebase project. The observer keeps the UI in sync
// when a sign-in or sign-out happens.
private struct AuthGate: View {
    let firebaseApp: FirebaseApp
    let tenantConfig: DSLScreen
    let tenantId: String
    @StateObject private var auth: AuthObserver

    init(firebaseApp: FirebaseApp, tenantConfig: DSLScreen, tenantId: String) {
        self.firebaseApp = firebaseApp
        self.tenantConfig = tenantConfig
        self.tenantId = tenantId
        _auth = StateObject(wrappedValue: AuthObserver(app: firebaseApp))
        // Stash for downstream views (env propagation through TabView/Nav was lossy).
        TenantContext.shared.functionsBaseURL = tenantConfig.functionsBaseURL.flatMap { URL(string: $0) }
        print("[CommuneRenderer] tenant=\(tenantId) functionsBaseURL=\(TenantContext.shared.functionsBaseURL?.absoluteString ?? "nil")")
    }

    var body: some View {
        if auth.user == nil {
            LoginForm(firebaseApp: firebaseApp, tenantTitle: tenantId)
        } else {
            renderTenant()
        }
    }

    @ViewBuilder
    private func renderTenant() -> some View {
        Group {
            if tenantConfig.view.type == "tabbar" {
                DSLView(node: tenantConfig.view, scope: DSLScope())
            } else {
                NavigationStack {
                    DSLView(node: tenantConfig.view, scope: DSLScope())
                        .navigationDestination(for: Route.self) { route in
                            ScreenView(qualifiedScreen: route.qualifiedScreen, initialBindings: route.bindings)
                        }
                }
            }
        }
        .environment(\.currentFirebaseApp, firebaseApp)
        .environment(\.currentFunctionsBaseURL, tenantConfig.functionsBaseURL.flatMap { URL(string: $0) })
    }

}

// Current module propagated implicitly through the view tree. CardBlock reads
// it to qualify unqualified `navigate.to` targets to the screen's owning module.
private struct CurrentModuleKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

// FirebaseApp owned by the active tenant. ScreenView reads this to query
// Firestore collections referenced by `firestore:<collection>` data sources.
private struct CurrentFirebaseAppKey: EnvironmentKey {
    static let defaultValue: FirebaseApp? = nil
}

// Base URL of the platform CDN/dev-server. ButtonBlock POSTs `cf` actions
// (form submissions) to `<baseURL>/cf/<module>/<endpoint>` when no
// production functionsBaseURL is set on the tenant.
private struct CurrentBaseURLKey: EnvironmentKey {
    static let defaultValue: URL? = nil
}

// Production Cloud Functions base URL declared by the tenant config. When
// set, ButtonBlock POSTs to `<functionsBaseURL>/<endpoint>` with a
// FirebaseAuth ID token instead of the dev-server pattern.
private struct CurrentFunctionsBaseURLKey: EnvironmentKey {
    static let defaultValue: URL? = nil
}

extension EnvironmentValues {
    var currentModule: String? {
        get { self[CurrentModuleKey.self] }
        set { self[CurrentModuleKey.self] = newValue }
    }
    var currentFirebaseApp: FirebaseApp? {
        get { self[CurrentFirebaseAppKey.self] }
        set { self[CurrentFirebaseAppKey.self] = newValue }
    }
    var currentBaseURL: URL? {
        get { self[CurrentBaseURLKey.self] }
        set { self[CurrentBaseURLKey.self] = newValue }
    }
    var currentFunctionsBaseURL: URL? {
        get { self[CurrentFunctionsBaseURLKey.self] }
        set { self[CurrentFunctionsBaseURLKey.self] = newValue }
    }
}

// Convert Firestore document fields (Any) to our typed DSLValue tree.
private func dslValue(from any: Any) -> DSLValue {
    switch any {
    case let s as String:
        return .string(s)
    case let n as NSNumber:
        if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
        let cType = CFNumberGetType(n as CFNumber)
        switch cType {
        case .floatType, .doubleType, .float32Type, .float64Type, .cgFloatType:
            return .double(n.doubleValue)
        default:
            return .int(n.intValue)
        }
    case let arr as [Any]:
        return .array(arr.map { dslValue(from: $0) })
    case let dict as [String: Any]:
        var result: [String: DSLValue] = [:]
        for (k, v) in dict { result[k] = dslValue(from: v) }
        return .object(result)
    default:
        return .null
    }
}

private struct FallbackNotFound: View {
    let label: String
    init(_ label: String) { self.label = label }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Écran introuvable")
                .font(.headline)
            Text("\(label) n'a pas été trouvé.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - ScreenView (renders a module screen identified by `<module>:<screen>`)

struct ScreenView: View {
    let qualifiedScreen: String
    let initialBindings: [String: DSLValue]
    @Environment(\.currentFirebaseApp) private var firebaseApp
    @State private var firestoreData: [String: DSLValue] = [:]
    @StateObject private var form = FormState()

    var body: some View {
        if let path = ModuleRegistry.shared.screenPath(qualified: qualifiedScreen),
           let dsl = ScreenLoader.loadScreen(at: path) {
            let currentModule = ModuleRegistry.shared.module(of: qualifiedScreen)
            let scope = makeScope(for: dsl, currentModule: currentModule)
            DSLView(node: dsl.view, scope: scope)
                .environment(\.currentModule, currentModule)
                .environmentObject(form)
                .navigationTitle(navTitle(dsl: dsl, scope: scope))
                .navigationBarTitleDisplayMode(displayMode(dsl.navigation?.displayMode))
                .task(id: qualifiedScreen) {
                    await loadFirestoreData(for: dsl)
                }
        } else {
            FallbackNotFound(qualifiedScreen)
        }
    }

    private func makeScope(for dsl: DSLScreen, currentModule: String?) -> DSLScope {
        var scope = DSLScope(bindings: initialBindings)
        scope = scope.adding("form", form.dslValue())
        for (key, source) in dsl.data ?? [:] {
            guard let mod = currentModule else { continue }
            if source.hasPrefix("@") {
                // Static data — looked up via the module's manifest data map.
                let dataName = String(source.dropFirst())
                if let path = ModuleRegistry.shared.dataPath(moduleId: mod, dataName: dataName),
                   let value = ScreenLoader.loadData(at: path) {
                    scope = scope.adding(key, value)
                }
            } else if source.hasPrefix("cf:") {
                // CF endpoint result, eagerly preloaded into PlatformAssets at startup.
                let endpoint = String(source.dropFirst(3))
                let cacheKey = AssetPreloader.cfCacheKey(moduleId: mod, endpoint: endpoint)
                if let data = PlatformAssets.shared.get(cacheKey),
                   let value = try? JSONDecoder().decode(DSLValue.self, from: data) {
                    scope = scope.adding(key, value)
                }
            } else if source.hasPrefix("firestore:") {
                // Lazy-loaded; populated by `loadFirestoreData(for:)` on appear.
                if let value = firestoreData[key] {
                    scope = scope.adding(key, value)
                }
            }
        }
        return scope
    }

    @MainActor
    private func loadFirestoreData(for dsl: DSLScreen) async {
        guard let app = firebaseApp else { return }
        var newData: [String: DSLValue] = [:]
        for (key, source) in dsl.data ?? [:] {
            guard source.hasPrefix("firestore:") else { continue }
            let path = String(source.dropFirst("firestore:".count))
            let segments = path.split(separator: "/").filter { !$0.isEmpty }
            // Firestore convention: even number of segments = single doc,
            // odd number = collection of docs.
            do {
                if segments.count % 2 == 0 && segments.count >= 2 {
                    let doc = try await Firestore.firestore(app: app).document(path).getDocument()
                    if let data = doc.data() {
                        var dict: [String: DSLValue] = [:]
                        for (k, v) in data { dict[k] = dslValue(from: v) }
                        newData[key] = .object(dict)
                    }
                } else {
                    let snapshot = try await Firestore.firestore(app: app)
                        .collection(path)
                        .getDocuments()
                    let array: [DSLValue] = snapshot.documents.map { doc in
                        var dict: [String: DSLValue] = [:]
                        for (k, v) in doc.data() { dict[k] = dslValue(from: v) }
                        return .object(dict)
                    }
                    newData[key] = .array(array)
                }
            } catch {
                print("ScreenView: firestore fetch failed \(path) — \(error.localizedDescription)")
            }
        }
        firestoreData = newData
    }

    private func navTitle(dsl: DSLScreen, scope: DSLScope) -> String {
        guard let raw = dsl.navigation?.title else { return "" }
        return Template.resolve(raw, scope: scope)
    }

    private func displayMode(_ raw: String?) -> NavigationBarItem.TitleDisplayMode {
        switch raw {
        case "inline": return .inline
        case "large": return .large
        default: return .automatic
        }
    }
}

// MARK: - Dispatcher

struct DSLView: View {
    let node: DSLNode
    let scope: DSLScope

    var body: some View {
        switch node.type {
        case "scroll":   ScrollContainer(node: node, scope: scope)
        case "vstack":   VStackContainer(node: node, scope: scope)
        case "hstack":   HStackContainer(node: node, scope: scope)
        case "header":   HeaderBlock(node: node, scope: scope)
        case "card":     CardBlock(node: node, scope: scope)
        case "image":    ImageBlock(node: node, scope: scope)
        case "text":     TextBlock(node: node, scope: scope)
        case "markdown": MarkdownBlock(node: node, scope: scope)
        case "for":      ForBlock(node: node, scope: scope)
        case "if":       IfBlock(node: node, scope: scope)
        case "tabbar":   TabBarBlock(node: node, scope: scope)
        case "segmented": SegmentedBlock(node: node, scope: scope)
        case "calendar": CalendarBlock(node: node, scope: scope)
        case "map":      MapBlock(node: node, scope: scope)
        case "field":    FieldBlock(node: node, scope: scope)
        case "button":   ButtonBlock(node: node, scope: scope)
        default:
            Text("Unknown node: \(node.type)")
                .foregroundStyle(.red)
                .padding(8)
                .background(Color.red.opacity(0.1))
        }
    }
}

// MARK: - Layout blocks

private struct ScrollContainer: View {
    let node: DSLNode
    let scope: DSLScope

    var body: some View {
        let children: [DSLNode] = node.children ?? (node.child.map { [$0] } ?? [])
        let content = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    DSLView(node: child, scope: scope)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        if node.refreshable == true {
            content.refreshable {
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
        } else {
            content
        }
    }
}

private struct VStackContainer: View {
    let node: DSLNode
    let scope: DSLScope

    var body: some View {
        // `fill: true` opt-in lets a screen-root vstack expand to the
        // available height (needed when one of its children — typically a
        // segmented or calendar — drives a flex layout). Default stays
        // content-sized so cards inside scrolls don't blow up.
        let stack = VStack(alignment: .leading, spacing: CGFloat(node.spacing ?? 8)) {
            ForEach(Array((node.children ?? []).enumerated()), id: \.offset) { _, child in
                DSLView(node: child, scope: scope)
            }
        }
        .padding(CGFloat(node.padding ?? 0))

        if node.fill == true {
            stack.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            stack.frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

private struct HStackContainer: View {
    let node: DSLNode
    let scope: DSLScope

    var body: some View {
        let alignment: VerticalAlignment = {
            switch node.align {
            case "top":    return .top
            case "bottom": return .bottom
            default:       return .center
            }
        }()
        HStack(alignment: alignment, spacing: CGFloat(node.spacing ?? 8)) {
            ForEach(Array((node.children ?? []).enumerated()), id: \.offset) { _, child in
                DSLView(node: child, scope: scope)
            }
        }
        .padding(CGFloat(node.padding ?? 0))
    }
}

// MARK: - Leaf and composite blocks

private struct HeaderBlock: View {
    let node: DSLNode
    let scope: DSLScope
    @Environment(\.currentModule) private var currentModule

    var body: some View {
        if let action = node.action, action.type == "navigate", let to = action.to {
            NavigationLink(value: makeRoute(to: to, with: action.with ?? [:])) {
                hero
            }
            .buttonStyle(.plain)
        } else {
            hero
        }
    }

    private var hero: some View {
        let title = Template.resolve(node.title ?? "", scope: scope)
        let eyebrow = Template.resolve(node.eyebrow ?? "", scope: scope)
        let imageURLString = Template.resolve(node.imageUrl ?? "", scope: scope)
        let aspect = node.aspectRatio.map { CGFloat($0) }
        let height = CGFloat(node.height ?? 240)
        let radius = CGFloat(node.cornerRadius ?? 0)
        let url = URL(string: imageURLString)

        // Sizing: aspectRatio wins when set (hero use), else fixed height
        // (default for full-bleed banners on detail screens).
        return Group {
            if let aspect {
                Color(.tertiarySystemFill)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(aspect, contentMode: .fit)
            } else {
                Color(.tertiarySystemFill)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
            }
        }
        .overlay {
            if let url, !imageURLString.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty, .failure:
                        Color(.tertiarySystemFill)
                    @unknown default:
                        Color(.tertiarySystemFill)
                    }
                }
            }
        }
        .overlay {
            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 6) {
                if !eyebrow.isEmpty {
                    Text(eyebrow)
                        .font(.system(size: 13, weight: .light, design: .serif).italic())
                        .foregroundStyle(.white.opacity(0.92))
                }
                if !title.isEmpty {
                    Text(title)
                        .font(.system(size: 26, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    private func makeRoute(to: String, with: [String: DSLValue]) -> Route {
        var resolved: [String: DSLValue] = [:]
        for (key, value) in with {
            if case .string(let s) = value {
                resolved[key] = Template.resolveValue(s, scope: scope)
            } else {
                resolved[key] = value
            }
        }
        let qualified = ModuleRegistry.shared.qualify(to, currentModule: currentModule)
        return Route(qualifiedScreen: qualified, bindings: resolved)
    }
}

private struct CardBlock: View {
    let node: DSLNode
    let scope: DSLScope
    @Environment(\.currentModule) private var currentModule

    var body: some View {
        if let action = node.action, action.type == "navigate", let to = action.to {
            NavigationLink(value: makeRoute(to: to, with: action.with ?? [:])) {
                content
            }
            .buttonStyle(.plain)
        } else if let action = node.action, action.type == "logout" {
            Button {
                // Sign out of every configured Firebase project so the next
                // tenant pick lands on the LoginForm again, then clear the
                // persisted tenant — observed via @AppStorage in CommuneShell.
                CommuneFirebase.signOutAll()
                UserDefaults.standard.removeObject(forKey: "communeShell.tenant")
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        Group {
            if let child = node.child {
                DSLView(node: child, scope: scope)
            } else {
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            // Disclosure indicator on tappable navigate cards (Apple
            // List-row convention). Logout/cf cards keep their explicit
            // labels, so no chevron there.
            if node.action?.type == "navigate" {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
                    .padding(12)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.4), lineWidth: 0.5)
        )
    }

    private func makeRoute(to: String, with: [String: DSLValue]) -> Route {
        var resolved: [String: DSLValue] = [:]
        for (key, value) in with {
            if case .string(let s) = value {
                resolved[key] = Template.resolveValue(s, scope: scope)
            } else {
                resolved[key] = value
            }
        }
        let qualified = ModuleRegistry.shared.qualify(to, currentModule: currentModule)
        return Route(qualifiedScreen: qualified, bindings: resolved)
    }
}

private struct ImageBlock: View {
    let node: DSLNode
    let scope: DSLScope

    var body: some View {
        // Two flavors:
        //   • SF Symbol when `systemName` is set (optionally boxed when `bg` is set)
        //   • Network image when `url` is set (default)
        if let symbol = node.systemName, !symbol.isEmpty {
            symbolView(systemName: symbol)
        } else {
            networkImage
        }
    }

    @ViewBuilder
    private func symbolView(systemName: String) -> some View {
        let size = CGFloat(node.height ?? 18)
        let icon = Image(systemName: systemName)
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(iconColor)
        if let bgName = node.bg, !bgName.isEmpty {
            let boxSize: CGFloat = 38
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(bgColor(named: bgName))
                .frame(width: boxSize, height: boxSize)
                .overlay(icon)
        } else {
            icon
        }
    }

    private var iconColor: Color {
        switch node.color {
        case "civic":     return .civicAccent
        case "terra":     return .civicTerra
        case "secondary": return .secondary
        case "tertiary":  return Color(.tertiaryLabel)
        case "accent":    return .accentColor
        case "white":     return .white
        case nil, "primary": return .primary
        default:          return .primary
        }
    }

    private func bgColor(named: String) -> Color {
        switch named {
        case "civic-soft":  return .civicAccentSoft
        case "terra-soft":  return .civicTerraSoft
        case "civic":       return .civicAccent
        case "terra":       return .civicTerra
        case "paper":       return Color(red: 0xFA / 255, green: 0xF8 / 255, blue: 0xF4 / 255)
        case "paper-deep":  return Color(red: 0xF2 / 255, green: 0xEF / 255, blue: 0xE8 / 255)
        default:            return Color(.systemGray6)
        }
    }

    @ViewBuilder
    private var networkImage: some View {
        let urlString = Template.resolve(node.url ?? "", scope: scope)
        let url = URL(string: urlString)
        let aspect = CGFloat(node.aspectRatio ?? 1.6)
        let explicitW = node.width.map { CGFloat($0) }
        let explicitH = node.height.map { CGFloat($0) }

        // Lock dimensions on a flexible Color base, then layer the image
        // as overlay so its scaledToFill content is clipped to those bounds.
        // Same pattern as HeaderBlock — robust against unbounded parents.
        Group {
            if let w = explicitW, let h = explicitH {
                Color(.tertiarySystemFill).frame(width: w, height: h)
            } else if let h = explicitH {
                Color(.tertiarySystemFill)
                    .frame(maxWidth: .infinity)
                    .frame(height: h)
            } else {
                Color(.tertiarySystemFill)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(aspect, contentMode: .fit)
            }
        }
        .overlay {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    Color(.tertiarySystemFill)
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Color(.tertiarySystemFill)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(.tertiary)
                        )
                @unknown default:
                    Color(.tertiarySystemFill)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: CGFloat(node.cornerRadius ?? 0), style: .continuous))
    }
}

private struct TextBlock: View {
    let node: DSLNode
    let scope: DSLScope

    var body: some View {
        let raw = Template.resolve(node.value ?? "", scope: scope)
        let value = (node.style == "caps") ? raw.uppercased() : raw
        Text(value)
            .font(font(for: node.style))
            .foregroundStyle(color(for: node.color, style: node.style))
            .modifier(BadgeModifier(active: node.style == "badge"))
            .tracking(tracking(for: node.style))
            .lineSpacing(lineSpacing(for: node.style))
            .multilineTextAlignment(textAlign(for: node.align))
            .frame(maxWidth: .infinity, alignment: frameAlign(for: node.align))
    }

    private func textAlign(for align: String?) -> TextAlignment {
        switch align {
        case "center":   return .center
        case "trailing": return .trailing
        default:         return .leading
        }
    }

    private func frameAlign(for align: String?) -> Alignment {
        switch align {
        case "center":   return .center
        case "trailing": return .trailing
        default:         return .leading
        }
    }

    private func font(for style: String?) -> Font {
        switch style {
        case "display":          return .system(size: 36, weight: .semibold, design: .serif)
        case "display-small":    return .system(size: 28, weight: .semibold, design: .serif)
        case "serif-title":      return .system(size: 22, weight: .medium, design: .serif)
        case "serif-title2":     return .system(size: 18, weight: .medium, design: .serif)
        case "eyebrow":          return .system(size: 13, weight: .light, design: .serif).italic()
        case "subhead-italic":   return .system(size: 14, weight: .light, design: .serif).italic()
        case "caps":             return .system(size: 11, weight: .medium)
        case "title":            return .title.weight(.bold)
        case "title2":           return .title2.weight(.semibold)
        case "title3":           return .title3.weight(.semibold)
        case "headline":         return .headline
        case "body":             return .body
        case "callout":          return .callout
        case "caption":          return .caption
        case "footnote":         return .footnote
        case "badge":            return .caption2.weight(.bold)
        default:                 return .body
        }
    }

    private func tracking(for style: String?) -> CGFloat {
        switch style {
        case "caps": return 0.7
        case "display", "display-small", "serif-title", "serif-title2": return -0.4
        default: return 0
        }
    }

    private func lineSpacing(for style: String?) -> CGFloat {
        switch style {
        case "display": return 2
        case "body", "callout": return 1
        default: return 0
        }
    }

    private func color(for color: String?, style: String?) -> Color {
        if style == "badge" { return .white }
        switch color {
        case "primary":   return .primary
        case "secondary": return .secondary
        case "tertiary":  return Color(.tertiaryLabel)
        case "accent":    return .accentColor
        case "civic":     return .civicAccent
        case "terra":     return .civicTerra
        default:          return .primary
        }
    }
}

private struct BadgeModifier: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active {
            content
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor)
                .clipShape(Capsule())
                .fixedSize()
        } else {
            content
        }
    }
}

// SwiftUI's Text(AttributedString) ignores block-level markdown structure
// (headings, paragraphs, lists collapse into a single inline run). To get
// native block layout we split the string into blocks ourselves and render
// each block with its own Text view, while still using AttributedString for
// inline emphasis (bold, italic, links).
private struct MarkdownBlock: View {
    let node: DSLNode
    let scope: DSLScope

    var body: some View {
        let raw = Template.resolve(node.value ?? "", scope: scope)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseBlocks(raw).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private enum MdBlock {
        case heading(level: Int, text: String)
        case bullet(String)
        case paragraph(String)
    }

    private func parseBlocks(_ md: String) -> [MdBlock] {
        var result: [MdBlock] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            if !paragraphLines.isEmpty {
                result.append(.paragraph(paragraphLines.joined(separator: " ")))
                paragraphLines.removeAll()
            }
        }

        for rawLine in md.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
            } else if line.hasPrefix("### ") {
                flushParagraph()
                result.append(.heading(level: 3, text: String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                flushParagraph()
                result.append(.heading(level: 2, text: String(line.dropFirst(3))))
            } else if line.hasPrefix("# ") {
                flushParagraph()
                result.append(.heading(level: 1, text: String(line.dropFirst(2))))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flushParagraph()
                result.append(.bullet(String(line.dropFirst(2))))
            } else {
                paragraphLines.append(line)
            }
        }
        flushParagraph()
        return result
    }

    @ViewBuilder
    private func blockView(_ block: MdBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(headingFont(level))
                .foregroundStyle(.primary)
                .padding(.top, level <= 2 ? 6 : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Text(inline(text))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .paragraph(let text):
            Text(inline(text))
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func inline(_ text: String) -> AttributedString {
        if let attr = try? AttributedString(markdown: text) {
            return attr
        }
        return AttributedString(text)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title.weight(.bold)
        case 2: return .title2.weight(.bold)
        case 3: return .title3.weight(.semibold)
        default: return .headline
        }
    }
}

// Pill segmented control : container gris clair, segment sélectionné en
// blanc avec ombre subtile, texte semi-bold sélectionné / regular muted
// unsélectionné. Switche entre `cases[<option.id>]` localement (state
// non-persisté pour le v0 — survit pas au navigation pop/push).
private struct SegmentedBlock: View {
    let node: DSLNode
    let scope: DSLScope
    @State private var selected: String

    init(node: DSLNode, scope: DSLScope) {
        self.node = node
        self.scope = scope
        let initial = node.defaultCase ?? node.options?.first?.id ?? ""
        self._selected = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(node.options ?? [], id: \.id) { opt in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selected = opt.id
                        }
                    } label: {
                        Text(opt.label)
                            .font(.system(size: 14, weight: selected == opt.id ? .semibold : .regular))
                            .foregroundColor(selected == opt.id
                                             ? Color(uiColor: .label)
                                             : Color(uiColor: .secondaryLabel))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(selected == opt.id
                                          ? Color(uiColor: .systemBackground)
                                          : Color.clear)
                                    .shadow(color: selected == opt.id
                                            ? Color.black.opacity(0.06)
                                            : Color.clear,
                                            radius: 3, y: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                Capsule().fill(Color(uiColor: .systemGray6))
            )
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if let cases = node.cases, let child = cases[selected] {
                DSLView(node: child, scope: scope)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// Brand header rendu en haut de chaque tab racine. Cache la nav bar
// système (cf TabBarBlock). Sur push (détail), la nav bar standard
// reprend, le brand header disparaît du fait du push.
private struct BrandHeader: View {
    let brand: DSLBrand

    var body: some View {
        VStack(spacing: 6) {
            if let label = brand.label, !label.isEmpty {
                Text(label)
                    .font(.system(size: 22, weight: .heavy, design: .serif))
                    .foregroundColor(parseHex(brand.textColor) ?? .primary)
                    .tracking(0.5)
            }
            if let dots = brand.dots, !dots.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(dots.enumerated()), id: \.offset) { _, hex in
                        Circle()
                            .fill(parseHex(hex) ?? .gray)
                            .frame(width: 7, height: 7)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(uiColor: .systemBackground))
    }

    private func parseHex(_ hex: String?) -> Color? {
        guard let hex else { return nil }
        let s = hex.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard let val = UInt32(s, radix: 16), s.count == 6 else { return nil }
        return Color(
            red: Double((val >> 16) & 0xFF) / 255,
            green: Double((val >> 8) & 0xFF) / 255,
            blue: Double(val & 0xFF) / 255
        )
    }
}

private struct TabBarBlock: View {
    let node: DSLNode
    let scope: DSLScope

    var body: some View {
        TabView {
            ForEach(Array((node.tabs ?? []).enumerated()), id: \.offset) { _, tab in
                NavigationStack {
                    VStack(spacing: 0) {
                        if let brand = node.brand {
                            BrandHeader(brand: brand)
                        }
                        ScreenView(
                            qualifiedScreen: tab.screen,
                            initialBindings: resolveBindings(tab.bindings ?? [:])
                        )
                    }
                    .toolbar(node.brand != nil ? .hidden : .visible, for: .navigationBar)
                    .navigationDestination(for: Route.self) { route in
                        ScreenView(qualifiedScreen: route.qualifiedScreen, initialBindings: route.bindings)
                    }
                }
                .tabItem {
                    Label(Template.resolve(tab.title, scope: scope),
                          systemImage: tab.icon)
                }
            }
        }
    }

    private func resolveBindings(_ raw: [String: DSLValue]) -> [String: DSLValue] {
        var resolved: [String: DSLValue] = [:]
        for (key, value) in raw {
            if case .string(let s) = value {
                resolved[key] = Template.resolveValue(s, scope: scope)
            } else {
                resolved[key] = value
            }
        }
        return resolved
    }
}

private struct ForBlock: View {
    let node: DSLNode
    let scope: DSLScope

    var body: some View {
        let alias = node.alias ?? "item"
        let items = scope.lookup(node.iterable ?? "")?.arrayValue ?? []

        VStack(alignment: .leading, spacing: CGFloat(node.spacing ?? 16)) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                if let child = node.child {
                    DSLView(node: child, scope: scope.adding(alias, item))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Custom SwiftUI month-view calendar — civic editorial direction.
// Reads `in: <events binding>` + `dateField: <key>` (ISO yyyy-MM-dd).
// Selected day = filled accent pill with white text; today = accent ring;
// days with events = small accent dot below the number.
// When `child` is set, it is rendered below the grid in a scope augmented with
// `exposes` (default "selectedEvents") = events of the selected day.
private struct CalendarBlock: View {
    let node: DSLNode
    let scope: DSLScope

    var body: some View {
        let events = scope.lookup(node.iterable ?? "")?.arrayValue ?? []
        let dateField = node.dateField ?? "date"
        return CalendarBlockBody(node: node, scope: scope, events: events, dateField: dateField)
    }
}

private struct CalendarBlockBody: View {
    let node: DSLNode
    let scope: DSLScope
    let events: [DSLValue]
    let dateField: String

    @State private var visibleMonth: Date = Self.startOfMonth(Date())
    @State private var selected: Date = Calendar.fr.startOfDay(for: Date())

    private static func startOfMonth(_ d: Date) -> Date {
        let comps = Calendar.fr.dateComponents([.year, .month], from: d)
        return Calendar.fr.date(from: comps) ?? d
    }

    private var markedKeys: Set<String> {
        Set(events.compactMap { $0.get([dateField])?.stringValue })
    }

    private var selectedKey: String { Self.iso(selected) }

    private var filteredEvents: [DSLValue] {
        events.filter { ($0.get([dateField])?.stringValue ?? "") == selectedKey }
    }

    private static func iso(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }

    var body: some View {
        VStack(spacing: 0) {
            calendarChrome
            if let child = node.child {
                let exposed = node.exposes ?? "selectedEvents"
                let augmented = scope
                    .adding(exposed, .array(filteredEvents))
                    .adding("\(exposed)Count", .int(filteredEvents.count))
                    .adding("\(exposed)DayLabel", .string(longDayLabel(selected)))
                    .adding("\(exposed)Pre", .string(Calendar.fr.isDateInToday(selected) ? "Aujourd'hui" : ""))
                DSLView(node: child, scope: augmented)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var calendarChrome: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 4) {
                    Text(monthLabel(visibleMonth))
                        .font(.system(size: 22, weight: .medium, design: .serif))
                        .foregroundStyle(Color.primary)
                    Text(yearLabel(visibleMonth))
                        .font(.system(size: 18, weight: .light, design: .serif).italic())
                        .foregroundStyle(Color.secondary)
                }
                Spacer()
                HStack(spacing: 2) {
                    chevronButton(systemName: "chevron.left") { changeMonth(by: -1) }
                    chevronButton(systemName: "chevron.right") { changeMonth(by: 1) }
                }
            }
            .padding(.horizontal, 6)

            HStack(spacing: 0) {
                ForEach(Calendar.frWeekdayLabels.indices, id: \.self) { idx in
                    Text(Calendar.frWeekdayLabels[idx])
                        .font(.system(size: 11, weight: .medium))
                        .kerning(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(idx >= 5 ? Color.secondary.opacity(0.6) : Color.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            let cells = monthGridDays(for: visibleMonth)
            VStack(spacing: 2) {
                ForEach(0..<cells.count / 7, id: \.self) { row in
                    HStack(spacing: 2) {
                        ForEach(0..<7, id: \.self) { col in
                            let date = cells[row * 7 + col]
                            DayCellView(
                                date: date,
                                inMonth: Calendar.fr.isDate(date, equalTo: visibleMonth, toGranularity: .month),
                                isToday: Calendar.fr.isDateInToday(date),
                                isSelected: Calendar.fr.isDate(date, inSameDayAs: selected),
                                hasEvent: markedKeys.contains(Self.iso(date))
                            )
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selected = Calendar.fr.startOfDay(for: date)
                                if !Calendar.fr.isDate(date, equalTo: visibleMonth, toGranularity: .month) {
                                    visibleMonth = Self.startOfMonth(date)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
                .padding(.horizontal, 18)
        }
    }

    private func chevronButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.secondary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color.clear))
        }
        .buttonStyle(.plain)
    }

    private func changeMonth(by delta: Int) {
        if let next = Calendar.fr.date(byAdding: .month, value: delta, to: visibleMonth) {
            visibleMonth = Self.startOfMonth(next)
        }
    }

    private func monthLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "LLLL"
        return f.string(from: d).lowercased()
    }

    private func yearLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "yyyy"
        return f.string(from: d)
    }

    private func longDayLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM"
        let s = f.string(from: d)
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// Returns 35 or 42 dates: the ISO Monday-anchored 6×7 grid for the month, trimmed
    /// to 5 rows when the last row would be entirely outside the visible month.
    private func monthGridDays(for month: Date) -> [Date] {
        let cal = Calendar.fr
        let first = cal.dateInterval(of: .month, for: month)?.start ?? month
        let weekdayMonFirst = (cal.component(.weekday, from: first) + 5) % 7
        let start = cal.date(byAdding: .day, value: -weekdayMonFirst, to: first) ?? first
        var dates: [Date] = []
        for i in 0..<42 {
            if let d = cal.date(byAdding: .day, value: i, to: start) {
                dates.append(d)
            }
        }
        // Trim 6th row when it's entirely outside the visible month
        if dates.count == 42, let row6First = dates.dropFirst(35).first,
           !cal.isDate(row6First, equalTo: month, toGranularity: .month) {
            return Array(dates.prefix(35))
        }
        return dates
    }
}

private struct DayCellView: View {
    let date: Date
    let inMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    let hasEvent: Bool

    var body: some View {
        ZStack {
            // Selected pill
            if isSelected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.civicAccent)
                    .padding(2)
            } else if isToday {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.civicAccent, lineWidth: 1.5)
                    .padding(4)
            }
            VStack(spacing: 2) {
                Text("\(Calendar.fr.component(.day, from: date))")
                    .font(.system(size: 15, weight: weight))
                    .foregroundStyle(numberColor)
                if hasEvent {
                    Circle()
                        .fill(isSelected ? Color.white.opacity(0.9) : Color.civicAccent)
                        .frame(width: 4, height: 4)
                        .padding(.top, -1)
                }
            }
        }
        .frame(height: 44)
    }

    private var weight: Font.Weight {
        if isSelected { return .semibold }
        if isToday { return .bold }
        return .medium
    }

    private var numberColor: Color {
        if isSelected { return .white }
        if !inMonth { return Color.secondary.opacity(0.45) }
        return Color.primary
    }
}

extension Calendar {
    static var fr: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.locale = Locale(identifier: "fr_FR")
        return c
    }

    static let frWeekdayLabels = ["L", "Ma", "Me", "J", "V", "S", "D"]
}

extension Color {
    static let civicAccent = Color(red: 0x2C / 255, green: 0x4A / 255, blue: 0x6B / 255)
    static let civicAccentSoft = Color(red: 0xDD / 255, green: 0xE6 / 255, blue: 0xF0 / 255)
    static let civicTerra = Color(red: 0xC8 / 255, green: 0x45 / 255, blue: 0x1B / 255)
    static let civicTerraSoft = Color(red: 0xF5 / 255, green: 0xE5 / 255, blue: 0xDD / 255)
    static let civicHair = Color(red: 0xE6 / 255, green: 0xE0 / 255, blue: 0xD6 / 255)
}

private struct IfBlock: View {
    let node: DSLNode
    let scope: DSLScope

    var body: some View {
        let conditionValue = Template.resolveValue(node.condition ?? "", scope: scope)
        if conditionValue.boolValue {
            if let then = node.then {
                DSLView(node: then, scope: scope)
            }
        } else if let elseNode = node.elseNode {
            DSLView(node: elseNode, scope: scope)
        }
    }
}
