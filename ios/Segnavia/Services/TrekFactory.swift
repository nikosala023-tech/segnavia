import Foundation
import CoreLocation

enum TrekFactory {
    /// Crea un trekking da una traccia, calcolando numeri e difficoltà di partenza.
    static func make(points raw: [TrackPoint], name: String, source: TrekSource, fileName: String? = nil, healthID: UUID? = nil) -> Trek {
        let stats = TrackStats(raw)
        let track = TrackMath.downsample(raw)
        let t = Trek(name: name, date: stats.start ?? raw.first?.time ?? .now,
                     difficulty: stats.gain > 1100 ? .EE : .E, source: source, healthWorkoutID: healthID,
                     fileName: fileName, track: track)
        t.apply(stats)
        return t
    }

    /// Località e regione del punto di partenza, via Apple.
    static func reverseGeocode(_ p: TrackPoint) async -> (String, String)? {
        guard let pm = try? await CLGeocoder().reverseGeocodeLocation(p.location, preferredLocale: Locale(identifier: "it_IT")).first else { return nil }
        let loc = pm.locality ?? pm.subLocality ?? pm.subAdministrativeArea ?? pm.name ?? ""
        let reg = pm.administrativeArea ?? pm.country ?? ""
        return (loc, reg)
    }

    @MainActor static func fillPlace(_ t: Trek) async {
        guard t.location.isEmpty, let first = t.track.first, let place = await reverseGeocode(first) else { return }
        let (loc, reg) = place
        t.location = loc; if t.region.isEmpty { t.region = reg }
        if t.name.isEmpty { t.name = loc.isEmpty ? "Trekking" : "Giro da \(loc)" }
    }
}
