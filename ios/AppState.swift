import Foundation
import CoreLocation
import SwiftUI

// ── Positioning method ─────────────────────────────────────────────────────
// The Web/iOS Geolocation API never tells you which sensor was used.
// We infer from accuracy, plus iOS 14 "Approximate Location" (reducedAccuracy)
// which is the only public API that GUARANTEES GPS is not in use.

enum PositioningMethod {
    case unknown
    case networkConfirmed   // iOS 14+ reducedAccuracy → OS has disabled GPS
    case likelyCellular     // accuracy ≥ 300m → almost certainly cell tower(s)
    case likelyWiFi         // 30–300m → likely WiFi AP triangulation
    case possiblyGPS        // < 30m → almost certainly GPS

    var label: String {
        switch self {
        case .unknown:           return "不明"
        case .networkConfirmed:  return "ネットワーク測位（GPS無し確定）"
        case .likelyCellular:    return "セル測位（推定）"
        case .likelyWiFi:        return "WiFi 測位（推定）"
        case .possiblyGPS:       return "GPS の可能性が高い"
        }
    }

    var isGPSFree: Bool {
        switch self {
        case .networkConfirmed, .likelyCellular, .likelyWiFi: return true
        default: return false
        }
    }

    // Colour shown in UI – yellow warns user that GPS might be active
    var tintColor: Color {
        switch self {
        case .possiblyGPS:      return .yellow
        case .networkConfirmed: return .green
        default:                return .cyan
        }
    }
}

// ── AppState ───────────────────────────────────────────────────────────────

final class AppState: NSObject, ObservableObject {

    // MARK: Location
    @Published var currentLocation: CLLocation?
    @Published var authStatus:    CLAuthorizationStatus = .notDetermined
    @Published var accuracyAuth:  CLAccuracyAuthorization = .fullAccuracy
    @Published var locationError: String?

    // MARK: Tracking
    @Published var isTracking    = false
    @Published var coordinates:  [CLLocationCoordinate2D] = []
    @Published var totalDistance: Double = 0
    @Published var activeSession: TrackSession?

    // MARK: Sessions
    @Published private(set) var sessions: [TrackSession] = []

    private let locManager = CLLocationManager()
    private var lastCLLocation: CLLocation?
    private let sessionsURL: URL = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("hmg_sessions.json")

    override init() {
        super.init()
        locManager.delegate = self
        // Low accuracy → OS prefers network/WiFi over GPS (power-efficiency)
        locManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locManager.distanceFilter  = 10
        authStatus = locManager.authorizationStatus
        if #available(iOS 14.0, *) { accuracyAuth = locManager.accuracyAuthorization }
        loadSessions()
    }

    // MARK: - Computed

    var positioningMethod: PositioningMethod {
        // reducedAccuracy = iOS has definitively turned off GPS
        if #available(iOS 14.0, *), accuracyAuth == .reducedAccuracy {
            return .networkConfirmed
        }
        guard let loc = currentLocation, loc.horizontalAccuracy > 0 else { return .unknown }
        switch loc.horizontalAccuracy {
        case ..<30:  return .possiblyGPS
        case ..<300: return .likelyWiFi
        default:     return .likelyCellular
        }
    }

    var speedKmh: Double? {
        guard let s = currentLocation?.speed, s >= 0 else { return nil }
        return s * 3.6
    }

    // MARK: - Permission

    func requestPermission() {
        locManager.requestWhenInUseAuthorization()
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Tracking

    func startTracking() {
        guard authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways else {
            requestPermission(); return
        }
        activeSession  = TrackSession()
        coordinates    = []
        totalDistance  = 0
        lastCLLocation = nil
        isTracking     = true
        locManager.startUpdatingLocation()
    }

    func stopTracking() {
        locManager.stopUpdatingLocation()
        isTracking = false
        guard var s = activeSession, !s.points.isEmpty else { activeSession = nil; return }
        s.endedAt  = .now
        s.distance = totalDistance
        upsertSession(s)
        activeSession = nil
    }

    func clearTrack() {
        coordinates    = []
        totalDistance  = 0
        lastCLLocation = nil
    }

    private func handleLocation(_ location: CLLocation) {
        currentLocation = location
        guard isTracking else { return }
        coordinates.append(location.coordinate)
        if let prev = lastCLLocation { totalDistance += prev.distance(from: location) }
        lastCLLocation = location
        activeSession?.points.append(TrackPoint(location))
        activeSession?.distance = totalDistance
        // Auto-save every 10 points so a crash doesn't lose the session
        if let s = activeSession, s.points.count % 10 == 0 {
            var saved = s; saved.endedAt = .now; upsertSession(saved)
        }
    }

    // MARK: - Sessions

    func upsertSession(_ session: TrackSession) {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.insert(session, at: 0)
        }
        persistSessions()
    }

    func deleteSession(_ session: TrackSession) {
        sessions.removeAll { $0.id == session.id }
        persistSessions()
    }

    private func persistSessions() {
        if let data = try? JSONEncoder().encode(sessions) { try? data.write(to: sessionsURL) }
    }

    private func loadSessions() {
        guard let data  = try? Data(contentsOf: sessionsURL),
              let items = try? JSONDecoder().decode([TrackSession].self, from: data)
        else { return }
        sessions = items
    }
}

// MARK: - CLLocationManagerDelegate

extension AppState: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last,
              loc.horizontalAccuracy > 0,
              loc.horizontalAccuracy < 5000,
              loc.timestamp.timeIntervalSinceNow > -15 else { return }
        DispatchQueue.main.async { self.handleLocation(loc) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let clErr = error as? CLError, clErr.code != .locationUnknown else { return }
        DispatchQueue.main.async { self.locationError = error.localizedDescription }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authStatus = manager.authorizationStatus
            if #available(iOS 14.0, *) { self.accuracyAuth = manager.accuracyAuthorization }
        }
    }
}
