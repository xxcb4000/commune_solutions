import SwiftUI

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
                .lineLimit((node.minLines ?? 4) ... max(8, node.minLines ?? 4))
                .textFieldStyle(.roundedBorder)
        case "yesno":
            let boolBinding = Binding<Bool>(
                get: { (form.values[id] ?? "false") == "true" },
                set: { form.values[id] = $0 ? "true" : "false" }
            )
            Toggle(isOn: boolBinding) { Text(label) }
        default:  // "text"
            TextField(placeholder, text: binding)
                .textFieldStyle(.roundedBorder)
        }
    }
}

struct ButtonBlock: View {
    let node: DSLNode
    let scope: DSLScope
    @Environment(\.currentModule) private var currentModule
    @Environment(\.currentBaseURL) private var baseURL
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
        guard let endpoint = action.endpoint,
              let mod = currentModule,
              let baseURL else {
            feedback = "Endpoint mal configuré"
            feedbackError = true
            return
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

        let url = baseURL.appendingPathComponent("cf/\(mod)/\(endpoint)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                feedback = "Envoyé."
                feedbackError = false
                form.values.removeAll()
            } else {
                feedback = "Erreur serveur"
                feedbackError = true
            }
        } catch {
            feedback = "Réseau : \(error.localizedDescription)"
            feedbackError = true
        }
    }
}
