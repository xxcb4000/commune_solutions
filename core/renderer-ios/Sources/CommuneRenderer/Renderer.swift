import SwiftUI
import UIKit
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
// (form submissions) to `<baseURL>/cf/<module>/<endpoint>`.
private struct CurrentBaseURLKey: EnvironmentKey {
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
        case "calendar": CalendarBlock(node: node, scope: scope)
        case "field":    FieldBlock(node: node)
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
        let content = ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array((node.children ?? []).enumerated()), id: \.offset) { _, child in
                    DSLView(node: child, scope: scope)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

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
        VStack(alignment: .leading, spacing: CGFloat(node.spacing ?? 8)) {
            ForEach(Array((node.children ?? []).enumerated()), id: \.offset) { _, child in
                DSLView(node: child, scope: scope)
            }
        }
        .padding(CGFloat(node.padding ?? 0))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HStackContainer: View {
    let node: DSLNode
    let scope: DSLScope

    var body: some View {
        HStack(alignment: .center, spacing: CGFloat(node.spacing ?? 8)) {
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

    var body: some View {
        let title = Template.resolve(node.title ?? "", scope: scope)
        let imageURLString = Template.resolve(node.imageUrl ?? "", scope: scope)
        let height = CGFloat(node.height ?? 240)
        let url = URL(string: imageURLString)

        // Lock dimensions on the base Color rect, then layer the image as an
        // overlay so its scaledToFill content is clipped to those bounds.
        Color(.tertiarySystemFill)
            .frame(maxWidth: .infinity)
            .frame(height: height)
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
                if !title.isEmpty {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(16)
                        .multilineTextAlignment(.leading)
                }
            }
            .clipped()
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
        let urlString = Template.resolve(node.url ?? "", scope: scope)
        let url = URL(string: urlString)
        let aspect = node.aspectRatio.map { CGFloat($0) }

        Group {
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
        .frame(maxWidth: .infinity)
        .aspectRatio(aspect, contentMode: .fill)
        .clipped()
    }
}

private struct TextBlock: View {
    let node: DSLNode
    let scope: DSLScope

    var body: some View {
        let value = Template.resolve(node.value ?? "", scope: scope)
        Text(value)
            .font(font(for: node.style))
            .foregroundStyle(color(for: node.color, style: node.style))
            .modifier(BadgeModifier(active: node.style == "badge"))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func font(for style: String?) -> Font {
        switch style {
        case "title": return .title.weight(.bold)
        case "title2": return .title2.weight(.semibold)
        case "title3": return .title3.weight(.semibold)
        case "headline": return .headline
        case "body": return .body
        case "callout": return .callout
        case "caption": return .caption
        case "footnote": return .footnote
        case "badge": return .caption2.weight(.bold)
        default: return .body
        }
    }

    private func color(for color: String?, style: String?) -> Color {
        if style == "badge" { return .white }
        switch color {
        case "primary": return .primary
        case "secondary": return .secondary
        case "tertiary": return Color(.tertiaryLabel)
        case "accent": return .accentColor
        default: return .primary
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

private struct TabBarBlock: View {
    let node: DSLNode
    let scope: DSLScope

    var body: some View {
        TabView {
            ForEach(Array((node.tabs ?? []).enumerated()), id: \.offset) { _, tab in
                NavigationStack {
                    ScreenView(
                        qualifiedScreen: tab.screen,
                        initialBindings: resolveBindings(tab.bindings ?? [:])
                    )
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

// Native month-view calendar (UICalendarView, iOS 16+) showing dots on dates
// that have an event. Reads `in: <events binding>` and `dateField: <key>` —
// each event's `dateField` is parsed as ISO `yyyy-MM-dd` and used as a marker.
// Default visible month = month of the earliest parseable event date.
private struct CalendarBlock: View {
    let node: DSLNode
    let scope: DSLScope

    var body: some View {
        let events = scope.lookup(node.iterable ?? "")?.arrayValue ?? []
        let dateField = node.dateField ?? "date"
        let isoStrings = events.compactMap { $0.get([dateField])?.stringValue }
        let markedKeys = Set(isoStrings)
        let firstISO = isoStrings.compactMap(parseISO).sorted().first

        CalendarRepresentable(
            markedISOKeys: markedKeys,
            visibleMonth: monthComponents(from: firstISO)
        )
        .frame(height: 360)
        .padding(.horizontal, 16)
    }

    private func parseISO(_ str: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: str)
    }

    private func monthComponents(from date: Date?) -> DateComponents {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let now = date ?? Date()
        let comps = cal.dateComponents([.year, .month], from: now)
        return DateComponents(year: comps.year, month: comps.month)
    }
}

private struct CalendarRepresentable: UIViewRepresentable {
    let markedISOKeys: Set<String>
    let visibleMonth: DateComponents

    func makeUIView(context: Context) -> UICalendarView {
        let cal = UICalendarView()
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.firstWeekday = 2  // Monday — fr-FR / ISO convention
        cal.calendar = gregorian
        cal.locale = Locale(identifier: "fr_FR")
        cal.delegate = context.coordinator
        cal.visibleDateComponents = visibleMonth
        return cal
    }

    func updateUIView(_ view: UICalendarView, context: Context) {
        context.coordinator.markedISOKeys = markedISOKeys
        view.visibleDateComponents = visibleMonth
        view.reloadDecorations(forDateComponents: [], animated: false)
    }

    func makeCoordinator() -> Coordinator { Coordinator(markedISOKeys: markedISOKeys) }

    final class Coordinator: NSObject, UICalendarViewDelegate {
        var markedISOKeys: Set<String>
        init(markedISOKeys: Set<String>) { self.markedISOKeys = markedISOKeys }

        func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            guard let y = dateComponents.year, let m = dateComponents.month, let d = dateComponents.day else { return nil }
            let key = String(format: "%04d-%02d-%02d", y, m, d)
            return markedISOKeys.contains(key) ? .default(color: .systemOrange, size: .large) : nil
        }
    }
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
