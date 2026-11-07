import Foundation
import CoreLocation

struct TrackStats {
    var distance: Double = 0
    var gain: Double = 0
    var loss: Double = 0
    var maxEle: Double?
    var minEle: Double?
    var duration: Double = 0
    var moving: Double = 0
    var start: Date?

    init() {}

    init(_ pts: [TrackPoint]) {
        guard pts.count > 1 else { return }
        let cum = TrackMath.cumulative(pts)
        distance = cum.last ?? 0
        let ele = TrackMath.smoothedElevation(pts, window: 3)
        var ref: Double?
        let threshold = 4.0 // isteresi per non sommare il rumore del GPS
        for case let v? in ele {
            maxEle = max(maxEle ?? v, v); minEle = min(minEle ?? v, v)
            guard let r = ref else { ref = v; continue }
            let d = v - r
            if d >= threshold { gain += d; ref = v } else if d <= -threshold { loss -= d; ref = v }
        }
        if let rawMax = pts.compactMap(\.ele).max() { maxEle = max(maxEle ?? rawMax, rawMax) }
        if let t0 = pts.first?.time, let t1 = pts.last?.time, t1 > t0 {
            start = t0; duration = t1.timeIntervalSince(t0)
            for i in 1..<pts.count {
                guard let a = pts[i - 1].time, let b = pts[i].time else { continue }
                let dt = b.timeIntervalSince(a)
                guard dt > 0, dt < 600 else { continue }
                if (cum[i] - cum[i - 1]) / dt > 0.25 { moving += dt }
            }
        }
    }
}

enum TrackMath {
    static func cumulative(_ pts: [TrackPoint]) -> [Double] {
        var c = [0.0]; c.reserveCapacity(pts.count)
        for i in 1..<max(pts.count, 1) { c.append(c[i - 1] + pts[i - 1].location.distance(from: pts[i].location)) }
        return c
    }

    static func smoothedElevation(_ pts: [TrackPoint], window w: Int) -> [Double?] {
        pts.indices.map { i in
            guard pts[i].ele != nil else { return nil }
            let vals = pts[max(0, i - w)...min(pts.count - 1, i + w)].compactMap(\.ele)
            return vals.reduce(0, +) / Double(vals.count)
        }
    }

    /// Pendenza in ogni punto, misurata su una finestra di ~150 m.
    static func grades(_ pts: [TrackPoint], cum: [Double], ele: [Double?]) -> [Double] {
        pts.indices.map { i in
            var j = i; while j < pts.count - 1 && cum[j] - cum[i] < 100 { j += 1 }
            var k = i; while k > 0 && cum[i] - cum[k] < 50 { k -= 1 }
            let dd = cum[j] - cum[k]
            guard dd > 10, let ej = ele[j], let ek = ele[k] else { return 0 }
            return (ej - ek) / dd
        }
    }

    /// Riduce la traccia a un numero gestibile di punti mantenendo la forma.
    static func downsample(_ pts: [TrackPoint], max: Int = 3000) -> [TrackPoint] {
        guard pts.count > max else { return pts }
        var out = [pts[0]]; var last = pts[0]
        for p in pts.dropFirst().dropLast() where last.location.distance(from: p.location) >= 6 { out.append(p); last = p }
        out.append(pts[pts.count - 1])
        guard out.count > max else { return out }
        let step = Double(out.count) / Double(max)
        var res = (0..<(max - 1)).map { out[Int(Double($0) * step)] }
        res.append(out[out.count - 1])
        return res
    }

    static func summitIndex(_ pts: [TrackPoint]) -> Int? {
        pts.indices.filter { pts[$0].ele != nil }.max { (pts[$0].ele ?? 0) < (pts[$1].ele ?? 0) }
    }
}
