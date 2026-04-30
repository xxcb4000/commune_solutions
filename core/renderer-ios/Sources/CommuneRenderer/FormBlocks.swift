import SwiftUI
import FirebaseAuth
import FirebaseCore

// Per-screen form state. Each ScreenView creates a fresh instance and exposes
// it both to fields (read/write) and to the surrounding scope (read via the
// `form.<id>` template binding).
@MainActor
final class FormState: ObservableObject {
    @Published var values: [String: String] = [:]

    func dslValue() -> DSLValue {
        var out: [String: DSLValue] = [:]
        for (k, v) in values { out[k] = .string(v) }
        return .object(out)
    }
}

struct FieldBlock: View {
    let node: DSLNode
    let scope: DSLScope
    @EnvironmentObject var form: FormState

    var body: some View {
        let kind = node.kind ?? "text"
        let fieldId = node.id ?? ""
        let label = node.label ?? ""
        let placeholder = node.placeholder ?? ""

        VStack(alignment: .leading, spacing: 6) {
            if !label.isEmpty && kind != "yesno" {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            content(kind: kind, id: fieldId, placeholder: placeholder, label: label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func content(kind: String, id: String, placeholder: String, label: String) -> some View {
        let binding = Binding<String>(
            get: { form.values[id] ?? "" },
            set: { form.values[id] = $0 }
        )
        switch kind {
        case "email":
            TextField(placeholder, text: binding)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
        case "secret":
            SecureField(placeholder, text: binding)
                .textFieldStyle(.roundedBorder)
        case "text.long":
            TextField(placeholder, text: binding, axis: .vertical)
                .lineLimit((node.minLines ?? 4) ... Swift.max(8, node.minLines ?? 4))
                .textFieldStyle(.roundedBorder)
        case "yesno":
            let boolBinding = Binding<Bool>(
                get: { (form.values[id] ?? "false") == "true" },
                set: { form.values[id] = $0 ? "true" : "false" }
            )
            Toggle(isOn: boolBinding) { Text(label) }
        case "radio":
            RadioGroup(node: node, fieldId: id, scope: scope)
        case "scale":
            ScaleField(node: node, fieldId: id)
        default:  // "text"
            TextField(placeholder, text: binding)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct RadioGroup: View {
    let node: DSLNode
    let fieldId: String
    let scope: DSLScope
    @EnvironmentObject var form: FormState

    var body: some View {
        let opts = resolveOptions()
        VStack(alignment: .leading, spacing: 8) {
            ForEach(opts, id: \.id) { opt in
                let selected = (form.values[fieldId] ?? "") == opt.id
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                    Text(opt.label)
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    form.values[fieldId] = opt.id
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resolveOptions() -> [DSLOption] {
        if let opts = node.options { return opts }
        guard let path = node.iterable else { return [] }
        let items = scope.lookup(path)?.arrayValue ?? []
        return items.compactMap { v -> DSLOption? in
            guard case .object(let dict) = v,
                  case .string(let id) = dict["id"] ?? .null,
                  case .string(let label) = dict["label"] ?? .null else { return nil }
            return DSLOption(id: id, label: label)
        }
    }
}

private struct ScaleField: View {
    let node: DSLNode
    let fieldId: String
    @EnvironmentObject var form: FormState

    var body: some View {
        let lower = node.min ?? 1
        let upper = node.max ?? 10
        let current = Double(form.values[fieldId] ?? "") ?? Double(lower)
        let binding = Binding<Double>(
            get: { current },
            set: { form.values[fieldId] = String(Int($0.rounded())) }
        )
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(Int(current.rounded()))")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("\(lower)–\(upper)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Slider(value: binding, in: Double(lower)...Double(upper), step: 1)
        }
    }
}

struct ButtonBlock: View {
    let node: DSLNode
    let scope: DSLScope
    @Environment(\.currentModule) private var currentModule
    @Environment(\.currentBaseURL) private var baseURL
    @Environment(\.currentFunctionsBaseURL) private var functionsBaseURL
    @Environment(\.currentFirebaseApp) private var firebaseApp
    @EnvironmentObject var form: FormState
    @State private var loading: Bool = false
    @State private var feedback: String?
    @State private var feedbackError: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            Button {
                Task { await handleAction() }
            } label: {
                Group {
                    if loading {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(node.label ?? "OK").frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(loading)

            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(feedbackError ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
    }

    @MainActor
    private func handleAction() async {
        guard let action = node.action else { return }
        switch action.type {
        case "cf":
            await submitCF(action: action)
        default:
            feedback = "Action non gérée: \(action.type)"
            feedbackError = true
        }
    }

    @MainActor
    private func submitCF(action: DSLAction) async {
        guard let endpoint = action.endpoint else {
            feedback = "Endpoint manquant"; feedbackError = true; return
        }
        loading = true
        feedback = nil
        defer { loading = false }

        // Resolve body via templating against current scope (form values included).
        var body: [String: Any] = [:]
        for (k, v) in action.body ?? [:] {
            if case .string(let s) = v {
                body[k] = Template.resolve(s, scope: scope)
            } else if let data = try? JSONEncoder().encode(v),
                      let any = try? JSONSerialization.jsonObject(with: data) {
                body[k] = any
            }
        }

        // Production CF (with auth) when tenant declares `functionsBaseURL`
        // (read from TenantContext singleton — env propagation was lossy
        // through TabView/NavigationStack); otherwise dev-server pattern.
        let url: URL
        var authToken: String?
        let prodURL = TenantContext.shared.functionsBaseURL ?? functionsBaseURL
        if let prodURL {
            url = prodURL.appendingPathComponent(endpoint)
            authToken = await fetchIDToken()
            if authToken == nil {
                feedback = "Non connecté — token Firebase indisponible"
                feedbackError = true
                return
            }
        } else if let devURL = baseURL, let mod = currentModule {
            url = devURL.appendingPathComponent("cf/\(mod)/\(endpoint)")
        } else {
            feedback = "URL backend non configurée"; feedbackError = true; return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let authToken {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                feedback = "Envoyé."
                feedbackError = false
                form.values.removeAll()
            } else if let http = response as? HTTPURLResponse {
                feedback = "Erreur serveur (\(http.statusCode))"
                feedbackError = true
            } else {
                feedback = "Erreur serveur"
                feedbackError = true
            }
        } catch {
            feedback = "Réseau : \(error.localizedDescription)"
            feedbackError = true
        }
    }

    private func fetchIDToken() async -> String? {
        guard let app = firebaseApp,
              let user = FirebaseAuth.Auth.auth(app: app).currentUser else { return nil }
        return try? await user.getIDToken()
    }
}
