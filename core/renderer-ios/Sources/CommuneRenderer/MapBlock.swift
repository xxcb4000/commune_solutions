import SwiftUI
import MapKit

// `map` primitive — renders a SwiftUI Map view with civic-styled pins
// driven by a Firestore-backed list. Same DSL contract as on Android.
//
// JSON shape:
//   { "type": "map",
//     "in": "places", "as": "place",
//     "latField": "lat", "lngField": "lng",
//     "categoryField": "category",
//     "height": 280,
//     "action": { "type": "navigate", "to": "detail",
//                 "with": { "place": "{{ place }}" } } }
struct MapBlock: View {
    let node: DSLNode
    let scope: DSLScope
    @Environment(\.currentModule) private var currentModule

    var body: some View {
        // Two modes:
        //   • `from: <key>` → single-point map (detail screen, one pin)
        //   • `in: <key>`   → collection map (list screen, many pins)
        let alias = node.alias ?? "place"
        let latKey = node.latField ?? "lat"
        let lngKey = node.lngField ?? "lng"
        let catKey = node.categoryField
        let height = CGFloat(node.height ?? 280)

        let places: [DSLValue]
        if let fromKey = node.from, let single = scope.lookup(fromKey) {
            places = [single]
        } else {
            places = scope.lookup(node.iterable ?? "")?.arrayValue ?? []
        }

        let items: [MapPlace] = places.enumerated().compactMap { (idx, place) in
            guard let lat = place.get([latKey])?.doubleValue,
                  let lng = place.get([lngKey])?.doubleValue else { return nil }
            let cat = catKey.flatMap { place.get([$0])?.stringValue }
            return MapPlace(id: idx, place: place, lat: lat, lng: lng, category: cat)
        }

        let region = Self.region(for: items)

        return Map(coordinateRegion: .constant(region), annotationItems: items) { item in
            MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: item.lat, longitude: item.lng)) {
                annotation(for: item, alias: alias)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private func annotation(for item: MapPlace, alias: String) -> some View {
        if let action = node.action, action.type == "navigate", let to = action.to {
            NavigationLink(value: makeRoute(to: to, with: action.with ?? [:], place: item.place, alias: alias)) {
                pin(category: item.category)
            }
            .buttonStyle(.plain)
        } else {
            pin(category: item.category)
        }
    }

    private func pin(category: String?) -> some View {
        ZStack {
            Circle()
                .fill(Self.color(for: category))
                .frame(width: 26, height: 26)
            Circle()
                .stroke(Color.white, lineWidth: 3)
                .frame(width: 26, height: 26)
        }
        .shadow(color: Color.black.opacity(0.20), radius: 3, y: 1)
    }

    private func makeRoute(to: String, with: [String: DSLValue], place: DSLValue, alias: String) -> Route {
        // Resolve any `{{ place }}` template references in the navigate.with
        // payload against a scope augmented with the tapped place. Mirrors the
        // pattern used by CardBlock for for-loop'd cards.
        let local = scope.adding(alias, place)
        var resolved: [String: DSLValue] = [:]
        for (key, value) in with {
            if case .string(let s) = value {
                resolved[key] = Template.resolveValue(s, scope: local)
            } else {
                resolved[key] = value
            }
        }
        let qualified = ModuleRegistry.shared.qualify(to, currentModule: currentModule)
        return Route(qualifiedScreen: qualified, bindings: resolved)
    }

    // Compute a region that fits all places with a margin. Falls back to a
    // central-Belgium area when the list is empty (renders an empty map
    // gracefully instead of zero-size).
    static func region(for items: [MapPlace]) -> MKCoordinateRegion {
        guard let first = items.first else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 50.5, longitude: 4.5),
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            )
        }
        var minLat = first.lat, maxLat = first.lat
        var minLng = first.lng, maxLng = first.lng
        for item in items.dropFirst() {
            minLat = min(minLat, item.lat); maxLat = max(maxLat, item.lat)
            minLng = min(minLng, item.lng); maxLng = max(maxLng, item.lng)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        // 1.6× padding around the bounding box; clamp to a minimum visible
        // span so a single point doesn't zoom in to street level.
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.012),
            longitudeDelta: max((maxLng - minLng) * 1.6, 0.012)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    static func color(for category: String?) -> Color {
        switch category {
        case "sport":    return Color(red: 0x6B/255, green: 0x7A/255, blue: 0x3D/255)
        case "culture":  return .civicTerra
        case "ecole":    return Color(red: 0x6B/255, green: 0x4F/255, blue: 0x8B/255)
        case "services": return .civicAccent
        case "nature":   return Color(red: 0x4F/255, green: 0x7B/255, blue: 0x5A/255)
        default:         return .civicAccent
        }
    }
}

struct MapPlace: Identifiable {
    let id: Int
    let place: DSLValue
    let lat: Double
    let lng: Double
    let category: String?
}
