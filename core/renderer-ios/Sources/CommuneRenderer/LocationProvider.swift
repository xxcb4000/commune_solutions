import Foundation
import CoreLocation

// Wrapper async/await autour de CLLocationManager pour la primitive
// d'action `device.location`. Le citoyen tape un bouton « Utiliser ma
// position » → la perm est demandée si pas accordée → la coord courante
// est captée → les fields lat/lng du form sont remplis.
//
// Pré-requis Info.plist : `NSLocationWhenInUseUsageDescription`.
// Le build commune devra agréger cette clé depuis les manifests qui
// déclarent `device.permissions: location.in-use` (phase 18.4 de la
// roadmap). Pour l'instant on l'ajoute hardcodée dans project.yml du
// spike.

enum LocationError: Error {
    case denied
    case restricted
    case unavailable
    case timeout

    var userMessage: String {
        switch self {
        case .denied:
            return "Localisation refusée. Active-la dans Réglages → Confidentialité."
        case .restricted:
            return "Localisation restreinte par les réglages parentaux."
        case .unavailable:
            return "Localisation indisponible (GPS off ou hors service)."
        case .timeout:
            return "Localisation trop lente (>10 s). Réessaie en extérieur."
        }
    }
}

@MainActor
final class LocationProvider: NSObject, CLLocationManagerDelegate {
    static let shared = LocationProvider()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Error>?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestCurrentLocation() async throws -> CLLocationCoordinate2D {
        // Si une demande est déjà en cours, on laisse l'appelant attendre.
        if let _ = continuation {
            // Pour rester simple, refuser la concurrence (UI typique : 1 bouton à la fois).
            throw LocationError.unavailable
        }

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            // Vérifier l'autorisation. requestWhenInUseAuthorization déclenche
            // la prompt système si pas encore demandée.
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
                // On attend le délégué didChangeAuthorization avant requestLocation
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .denied:
                resume(throwing: LocationError.denied)
            case .restricted:
                resume(throwing: LocationError.restricted)
            @unknown default:
                resume(throwing: LocationError.unavailable)
            }

            // Timeout 10s — sur device, ça suffit en extérieur. En intérieur
            // CoreLocation peut être lent ; mieux vaut couper et redemander
            // au user que de bloquer indéfiniment.
            self.timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                await MainActor.run { self?.resume(throwing: LocationError.timeout) }
            }
        }
    }

    private func resume(returning coord: CLLocationCoordinate2D) {
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(returning: coord)
        continuation = nil
    }

    private func resume(throwing error: Error) {
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation?.resume(throwing: error)
        continuation = nil
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor in
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                if continuation != nil {
                    manager.requestLocation()
                }
            case .denied:
                resume(throwing: LocationError.denied)
            case .restricted:
                resume(throwing: LocationError.restricted)
            case .notDetermined:
                break
            @unknown default:
                resume(throwing: LocationError.unavailable)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        let coord = location.coordinate
        Task { @MainActor in resume(returning: coord) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in resume(throwing: LocationError.unavailable) }
    }
}
