import Foundation
import CoreLocation

struct TrackPoint: Codable, Identifiable {
    var id = UUID()
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let speed: Double?      // m/s, nil if unavailable
    let timestamp: Date

    init(_ loc: CLLocation) {
        latitude  = loc.coordinate.latitude
        longitude = loc.coordinate.longitude
        accuracy  = max(0, loc.horizontalAccuracy)
        speed     = loc.speed >= 0 ? loc.speed : nil
        timestamp = loc.timestamp
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var clLocation: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
}

struct TrackSession: Codable, Identifiable {
    var id        = UUID()
    var name:     String
    let startedAt: Date
    var endedAt:  Date?
    var points:   [TrackPoint] = []
    var distance: Double = 0    // meters, cached

    init() {
        let fmt       = DateFormatter()
        fmt.locale    = Locale(identifier: "ja_JP")
        fmt.dateStyle = .short
        fmt.timeStyle = .short
        name      = fmt.string(from: .now)
        startedAt = .now
    }

    var duration: TimeInterval? { endedAt.map { $0.timeIntervalSince(startedAt) } }

    var formattedDuration: String {
        guard let d = duration else { return "--" }
        let h = Int(d) / 3600, m = Int(d) % 3600 / 60, s = Int(d) % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    var formattedDistance: String {
        distance >= 1000
            ? String(format: "%.2f km", distance / 1000)
            : String(format: "%.0f m",  distance)
    }
}
