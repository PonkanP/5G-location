import Foundation

// MARK: - GPX

enum GPXExporter {
    static func content(for session: TrackSession) -> String {
        let iso = ISO8601DateFormatter()
        let pts = session.points.map { p in
            """
                  <trkpt lat="\(f7(p.latitude))" lon="\(f7(p.longitude))">
                    <time>\(iso.string(from: p.timestamp))</time>
                    <hdop>\(String(format: "%.1f", p.accuracy / 5))</hdop>
                  </trkpt>
            """
        }.joined(separator: "\n")

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="5G Location Map"
          xmlns="http://www.topografix.com/GPX/1/1">
          <metadata>
            <name>\(xml(session.name))</name>
            <time>\(iso.string(from: session.startedAt))</time>
          </metadata>
          <trk>
            <name>\(xml(session.name))</name>
            <trkseg>
        \(pts)
            </trkseg>
          </trk>
        </gpx>
        """
    }

    // Write to a temp file and return the URL (for share sheet)
    static func tempURL(for session: TrackSession) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("5g-track-\(Int(session.startedAt.timeIntervalSince1970)).gpx")
        try content(for: session).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - CSV

enum CSVExporter {
    static func content(for session: TrackSession) -> String {
        let iso = ISO8601DateFormatter()
        var rows = ["timestamp,latitude,longitude,accuracy_m,speed_kmh"]
        for p in session.points {
            let spd = p.speed.map { String(format: "%.2f", $0 * 3.6) } ?? ""
            rows.append([
                iso.string(from: p.timestamp),
                f7(p.latitude), f7(p.longitude),
                "\(Int(p.accuracy))", spd,
            ].joined(separator: ","))
        }
        return rows.joined(separator: "\r\n")
    }

    static func tempURL(for session: TrackSession) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("5g-track-\(Int(session.startedAt.timeIntervalSince1970)).csv")
        // UTF-8 BOM for Excel compatibility
        var content = "\u{FEFF}" + content(for: session)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

// MARK: - Helpers

private func f7(_ v: Double) -> String { String(format: "%.7f", v) }

private func xml(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;")
     .replacingOccurrences(of: "<", with: "&lt;")
     .replacingOccurrences(of: ">", with: "&gt;")
}
