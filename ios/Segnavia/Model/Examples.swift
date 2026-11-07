import Foundation
import SwiftData
import CoreLocation

/// Quattro trekking finti (marcati "Esempio") per mostrare l'app al primo avvio.
enum Examples {
    @MainActor static func seedIfNeeded(_ context: ModelContext) {
        let key = "examplesSeeded"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let count = (try? context.fetchCount(FetchDescriptor<Trek>())) ?? 0
        if count == 0 { insert(context) }
    }

    @MainActor static func insert(_ context: ModelContext) {
        let iso = ISO8601DateFormatter()
        func mk(_ name: String, _ loc: String, _ reg: String, _ d: Difficulty, _ rating: Int, _ comp: String, _ notes: String,
                _ wps: [(Double, Double, Double)], _ start: String, outAndBack: Bool, seed: Int) {
            let pts = synth(wps, start: iso.date(from: start) ?? .now, outAndBack: outAndBack, seed: seed)
            let t = TrekFactory.make(points: pts, name: name, source: .example)
            t.location = loc; t.region = reg; t.difficulty = d; t.rating = rating; t.companions = comp; t.notes = notes
            context.insert(t)
        }
        mk("Giro delle Tre Cime di Lavaredo", "Auronzo di Cadore", "Veneto", .E, 5, "Giulia, Marco",
           "Partenza presto dal Rifugio Auronzo per evitare la folla. Luce pazzesca sulla parete nord dalla Forcella Lavaredo. Pranzo al Locatelli.",
           [(46.6122, 12.2955, 2320), (46.6146, 12.3040, 2310), (46.6176, 12.3080, 2344), (46.6223, 12.3108, 2454), (46.6326, 12.3088, 2405),
            (46.6352, 12.2990, 2290), (46.6313, 12.2890, 2283), (46.6262, 12.2852, 2355), (46.6200, 12.2880, 2315), (46.6122, 12.2955, 2320)],
           "2026-08-14T07:10:00+02:00", outAndBack: false, seed: 7)
        mk("Lago di Sorapis", "Cortina d'Ampezzo", "Veneto", .E, 4, "",
           "Sentiero 215 dal Passo Tre Croci. Qualche tratto attrezzato con cavo, niente di difficile. Il lago è davvero color turchese.",
           [(46.5555, 12.2040, 1805), (46.5490, 12.2080, 1835), (46.5405, 12.2140, 1875), (46.5315, 12.2180, 1905), (46.5250, 12.2200, 1965),
            (46.5195, 12.2196, 1928), (46.5176, 12.2214, 1925)],
           "2026-07-05T08:30:00+02:00", outAndBack: true, seed: 11)
        mk("Rifugio Vittorio Emanuele II", "Valsavarenche", "Valle d'Aosta", .E, 4, "Luca",
           "Salita regolare da Pont, stambecchi sopra i 2400. Vista sul Ciarforon e sul ghiacciaio del Gran Paradiso.",
           [(45.5307, 7.2009, 1960), (45.5262, 7.2045, 2080), (45.5228, 7.2112, 2230), (45.5196, 7.2160, 2380), (45.5160, 7.2214, 2530),
            (45.5128, 7.2268, 2650), (45.5108, 7.2306, 2732)],
           "2026-09-20T08:00:00+02:00", outAndBack: true, seed: 23)
        mk("Monte Grona", "Plesio", "Lombardia", .EE, 5, "Sara",
           "Dalla Breglia al Rifugio Menaggio, poi cresta finale con passaggi esposti. Panorama su tutto il Lago di Como.",
           [(46.0350, 9.2050, 750), (46.0385, 9.2095, 900), (46.0420, 9.2140, 1080), (46.0455, 9.2175, 1260), (46.0478, 9.2195, 1383),
            (46.0510, 9.2170, 1520), (46.0540, 9.2140, 1650), (46.0560, 9.2120, 1736)],
           "2025-10-12T08:45:00+02:00", outAndBack: true, seed: 31)
        try? context.save()
    }

    /// Interpola i punti con tornanti finti; tempi dalla funzione di Tobler.
    static func synth(_ wps: [(Double, Double, Double)], start: Date, outAndBack: Bool, seed: Int) -> [TrackPoint] {
        var s = seed
        func rnd() -> Double { s = (s * 9301 + 49297) % 233280; return Double(s) / 233280 }
        var route = wps.map { TrackPoint(lat: $0.0, lon: $0.1, ele: $0.2) }
        if outAndBack { route += route.dropLast().reversed() }
        var pts: [TrackPoint] = []
        for i in 0..<(route.count - 1) {
            let a = route[i], b = route[i + 1]
            let d = a.location.distance(from: b.location)
            let n = max(2, Int((d / 20).rounded()))
            let steep = abs((b.ele ?? 0) - (a.ele ?? 0)) / max(d, 1)
            let amp = steep > 0.15 ? 0.00028 : 0.00008, freq = steep > 0.15 ? 9.0 : 3.0
            let nx = -(b.lon - a.lon), ny = b.lat - a.lat, nl = max(hypot(nx, ny), 1e-9)
            for j in 0..<n {
                let f = Double(j) / Double(n)
                let w = sin(f * .pi) * sin(f * .pi * freq + Double(i)) * amp
                pts.append(TrackPoint(lat: a.lat + (b.lat - a.lat) * f + nx / nl * w * 0.7,
                                      lon: a.lon + (b.lon - a.lon) * f + ny / nl * w,
                                      ele: (a.ele ?? 0) + ((b.ele ?? 0) - (a.ele ?? 0)) * f + (rnd() - 0.5) * 3))
            }
        }
        pts.append(route[route.count - 1])
        var t = start
        for i in pts.indices {
            if i > 0 {
                let d = pts[i - 1].location.distance(from: pts[i].location)
                let sl = ((pts[i].ele ?? 0) - (pts[i - 1].ele ?? 0)) / max(d, 1)
                let v = 6 * exp(-3.5 * abs(sl + 0.05)) * 0.82 / 3.6
                t = t.addingTimeInterval(d / v + (i % 140 == 0 ? 480 : 0))
            }
            pts[i].time = t
        }
        return pts
    }
}
