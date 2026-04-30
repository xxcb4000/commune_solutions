import Foundation

// Polymorphic JSON value used for data bindings and runtime templating.
enum DSLValue: Codable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([DSLValue])
    case object([String: DSLValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([DSLValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: DSLValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Cannot decode DSLValue")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    var stringValue: String {
        switch self {
        case .null: return ""
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .string(let s): return s
        case .array(let a): return a.map { $0.stringValue }.joined(separator: ", ")
        case .object: return "[object]"
        }
    }

    var boolValue: Bool {
        switch self {
        case .null: return false
        case .bool(let b): return b
        case .int(let i): return i != 0
        case .double(let d): return d != 0
        case .string(let s): return !s.isEmpty && s != "false" && s != "0"
        case .array(let a): return !a.isEmpty
        case .object(let o): return !o.isEmpty
        }
    }

    var arrayValue: [DSLValue]? {
        if case .array(let a) = self { return a } else { return nil }
    }

    func get(_ path: [String]) -> DSLValue? {
        var current: DSLValue = self
        for part in path {
            switch current {
            case .object(let o):
                guard let next = o[part] else { return nil }
                current = next
            case .array(let a):
                guard let idx = Int(part), idx >= 0, idx < a.count else { return nil }
                current = a[idx]
            default:
                return nil
            }
        }
        return current
    }
}

struct DSLAction: Codable {
    let type: String
    let to: String?
    let with: [String: DSLValue]?
    let endpoint: String?              // for `cf`
    let body: [String: DSLValue]?      // for `cf`
    let onSuccess: [String: DSLValue]?  // optional follow-up (toast, navigate)
}

struct DSLTab: Decodable {
    let title: String
    let icon: String
    let screen: String
    let bindings: [String: DSLValue]?
}

struct DSLNavigation: Decodable {
    let title: String?
    let displayMode: String?
}

final class DSLNode: Decodable {
    let type: String
    let title: String?
    let subtitle: String?
    let value: String?
    let url: String?
    let imageUrl: String?
    let style: String?
    let color: String?
    let height: Double?
    let spacing: Double?
    let padding: Double?
    let aspectRatio: Double?
    let refreshable: Bool?
    let condition: String?
    let iterable: String?
    let alias: String?
    let dateField: String?
    let action: DSLAction?
    let children: [DSLNode]?
    let child: DSLNode?
    let then: DSLNode?
    let elseNode: DSLNode?
    let tabs: [DSLTab]?
    // Form primitives:
    let kind: String?         // "text" | "email" | "secret" | "text.long" | "yesno"
    let id: String?
    let label: String?
    let placeholder: String?
    let required: Bool?
    let minLines: Int?

    enum CodingKeys: String, CodingKey {
        case type, title, subtitle, value, url, imageUrl, style, color
        case height, spacing, padding, aspectRatio, refreshable, condition
        case action, children, child, then, tabs, dateField
        case kind, id, label, placeholder, required, minLines
        case iterable = "in"
        case alias = "as"
        case elseNode = "else"
    }
}

final class DSLScreen: Decodable {
    let screen: String?
    let tenant: String?
    let firebase: String?
    let navigation: DSLNavigation?
    let data: [String: String]?
    let view: DSLNode
    let modules: [DSLModuleRef]?
}

struct DSLModuleRef: Decodable {
    let id: String
    let version: String
}

struct Manifest: Decodable {
    let id: String
    let version: String
    let displayName: String
    let icon: String?
    let screens: [String: String]
    let data: [String: String]?
}
