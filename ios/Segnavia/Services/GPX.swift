import Foundation

struct ParsedTrack {
    var name: String
    var points: [TrackPoint]
}

enum GPXError: LocalizedError {
    case unreadable(String), empty(String)
    var errorDescription: String? {
        switch self {
        case .unreadable(let f): "\(f): file non leggibile"
        case .empty(let f): "\(f): nessuna traccia trovata"
        }
    }
}

/// Legge GPX (trkpt/rtept) e TCX (Trackpoint).
final class TrackFileParser: NSObject, XMLParserDelegate {
    private var points: [TrackPoint] = []
    private var current: TrackPoint?
    private var text = ""
    private var name = ""
    private var inTrkName = false
    private var depthTrk = false
    private var tcxLat: Double?, tcxLon: Double?, tcxEle: Double?, tcxTime: Date?
    private static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    private static let isoPlain = ISO8601DateFormatter()

    static func parse(data: Data, fileName: String) throws -> ParsedTrack {
        let p = TrackFileParser()
        let xml = XMLParser(data: data); xml.delegate = p; xml.shouldProcessNamespaces = true
        guard xml.parse() || !p.points.isEmpty else { throw GPXError.unreadable(fileName) }
        guard p.points.count > 1 else { throw GPXError.empty(fileName) }
        let cleaned = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let generic = cleaned.range(of: #"^(route|track|activity|percorso)[\s_-]*\d*"#, options: [.regularExpression, .caseInsensitive]) != nil
        return ParsedTrack(name: generic ? "" : cleaned, points: p.points)
    }

    private func date(_ s: String) -> Date? { Self.iso.date(from: s) ?? Self.isoPlain.date(from: s) }

    func parser(_ parser: XMLParser, didStartElement el: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        text = ""
        switch el {
        case "trk": depthTrk = true
        case "trkpt", "rtept":
            if let la = Double(a["lat"] ?? ""), let lo = Double(a["lon"] ?? "") { current = TrackPoint(lat: la, lon: lo) }
        case "name": inTrkName = depthTrk && current == nil && name.isEmpty
        case "Trackpoint": tcxLat = nil; tcxLon = nil; tcxEle = nil; tcxTime = nil
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
    func parser(_ parser: XMLParser, didEndElement el: String, namespaceURI: String?, qualifiedName: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch el {
        case "ele": if current != nil { current?.ele = Double(t) }
        case "time": if current != nil { current?.time = date(t) }
        case "trkpt", "rtept": if let c = current { points.append(c) }; current = nil
        case "name": if inTrkName { name = t; inTrkName = false }
        case "LatitudeDegrees": tcxLat = Double(t)
        case "LongitudeDegrees": tcxLon = Double(t)
        case "AltitudeMeters": tcxEle = Double(t)
        case "Time": tcxTime = date(t)
        case "Trackpoint": if let la = tcxLat, let lo = tcxLon { points.append(TrackPoint(lat: la, lon: lo, ele: tcxEle, time: tcxTime)) }
        default: break
        }
        text = ""
    }
}

enum GPXWriter {
    static func gpx(for trek: Trek) -> String {
        let iso = ISO8601DateFormatter()
        func x(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        let pts = trek.track.map { p in
            var s = "<trkpt lat=\"\(p.lat)\" lon=\"\(p.lon)\">"
            if let e = p.ele { s += "<ele>\(String(format: "%.1f", e))</ele>" }
            if let t = p.time { s += "<time>\(iso.string(from: t))</time>" }
            return s + "</trkpt>"
        }.joined(separator: "\n      ")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Segnavia" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata><name>\(x(trek.name))</name><time>\(iso.string(from: trek.date))</time></metadata>
          <trk><name>\(x(trek.name))</name><type>hiking</type><desc>\(x(trek.placeLine))</desc>
            <trkseg>
              \(pts)
            </trkseg>
          </trk>
        </gpx>
        """
    }

    static func fileURL(for trek: Trek) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(trek.name.slug + ".gpx")
        try gpx(for: trek).write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

extension String {
    var slug: String {
        let s = folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return s.isEmpty ? "trekking" : s
    }
}
