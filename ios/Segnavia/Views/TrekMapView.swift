import SwiftUI
import MapKit

enum MapLayer: String, CaseIterable, Identifiable {
    case topo, standard, satellite
    var id: String { rawValue }
    var label: String {
        switch self { case .topo: "Topografica"; case .standard: "Apple"; case .satellite: "Satellite" }
    }
}

struct MapTrack: Identifiable, Equatable {
    let id: UUID
    let coords: [CLLocationCoordinate2D]
    var summit: (CLLocationCoordinate2D, Double)?
    static func == (a: MapTrack, b: MapTrack) -> Bool { a.id == b.id && a.coords.count == b.coords.count }

    init(trek: Trek, withSummit: Bool = false) {
        id = trek.id
        coords = trek.track.map(\.coordinate)
        if withSummit, let i = TrackMath.summitIndex(trek.track), let e = trek.track[i].ele { summit = (trek.track[i].coordinate, e) }
    }
    init(id: UUID, coords: [CLLocationCoordinate2D]) { self.id = id; self.coords = coords }
}

/// Mappa con tessere OpenTopoMap + sentieri Waymarked Trails, oppure Apple standard/satellite.
struct TrekMapView: UIViewRepresentable {
    var tracks: [MapTrack]
    var layer: MapLayer
    var showTrails: Bool = true
    var selected: UUID? = nil
    var cursor: CLLocationCoordinate2D? = nil
    var showsUser: Bool = false
    var follow: Bool = false
    var edgePadding = UIEdgeInsets(top: 50, left: 30, bottom: 50, right: 30)
    var onSelect: ((UUID) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsCompass = true
        map.showsScale = true
        map.pointOfInterestFilter = .excludingAll
        map.register(PinView.self, forAnnotationViewWithReuseIdentifier: "pin")
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        map.addGestureRecognizer(tap)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let c = context.coordinator
        c.parent = self
        map.showsUserLocation = showsUser
        if follow { map.setUserTrackingMode(.follow, animated: true) }

        // tessere
        let tileKey = "\(layer.rawValue)-\(showTrails)"
        if c.tileKey != tileKey {
            c.tileKey = tileKey
            map.removeOverlays(map.overlays.filter { $0 is MKTileOverlay })
            switch layer {
            case .topo:
                let topo = MKTileOverlay(urlTemplate: "https://tile.opentopomap.org/{z}/{x}/{y}.png")
                topo.canReplaceMapContent = true; topo.maximumZ = 17
                map.insertOverlay(topo, at: 0, level: .aboveLabels)
                map.preferredConfiguration = MKStandardMapConfiguration()
            case .standard:
                map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .muted)
            case .satellite:
                map.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .realistic)
            }
            if showTrails && layer != .satellite {
                let trails = MKTileOverlay(urlTemplate: "https://tile.waymarkedtrails.org/hiking/{z}/{x}/{y}.png")
                trails.maximumZ = 18
                map.insertOverlay(trails, at: layer == .topo ? 1 : 0, level: .aboveLabels)
            }
            // le tracce devono restare sopra alle tessere
            let lines = map.overlays.filter { $0 is MKPolyline }
            map.removeOverlays(lines); map.addOverlays(lines, level: .aboveLabels)
        }

        // tracce
        let trackKey = tracks.map { "\($0.id)-\($0.coords.count)" }.joined(separator: ",") + "|\(selected?.uuidString ?? "")"
        if c.trackKey != trackKey {
            let first = c.trackKey == nil || c.trackIDs != tracks.map(\.id)
            c.trackKey = trackKey; c.trackIDs = tracks.map(\.id)
            map.removeOverlays(map.overlays.filter { $0 is MKPolyline })
            map.removeAnnotations(map.annotations.filter { ($0 as? Pin)?.kind != .cursor && !($0 is MKUserLocation) })
            var rect = MKMapRect.null
            for t in tracks where t.coords.count > 1 {
                let isSel = selected == nil || selected == t.id
                let casing = TrackLine(coordinates: t.coords, count: t.coords.count); casing.role = .casing; casing.trackID = t.id; casing.dim = !isSel
                let line = TrackLine(coordinates: t.coords, count: t.coords.count); line.role = .line; line.trackID = t.id; line.dim = !isSel
                map.addOverlays([casing, line], level: .aboveLabels)
                rect = rect.union(line.boundingMapRect)
                map.addAnnotation(Pin(kind: .start, coordinate: t.coords[0], trackID: t.id))
                if tracks.count == 1, let last = t.coords.last,
                   CLLocation(latitude: last.latitude, longitude: last.longitude).distance(from: CLLocation(latitude: t.coords[0].latitude, longitude: t.coords[0].longitude)) > 60 {
                    map.addAnnotation(Pin(kind: .end, coordinate: last, trackID: t.id))
                }
                if let s = t.summit { map.addAnnotation(Pin(kind: .summit, coordinate: s.0, trackID: t.id, title: "▲ \(Fmt.m(s.1)) m")) }
            }
            if first, !rect.isNull { map.setVisibleMapRect(rect, edgePadding: edgePadding, animated: false) }
        }

        // cursore dal profilo altimetrico
        if let cur = cursor {
            if let pin = c.cursorPin { pin.coordinate = cur } else {
                let p = Pin(kind: .cursor, coordinate: cur, trackID: nil); c.cursorPin = p; map.addAnnotation(p)
            }
        } else if let p = c.cursorPin { map.removeAnnotation(p); c.cursorPin = nil }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: TrekMapView
        var tileKey: String?
        var trackKey: String?
        var trackIDs: [UUID] = []
        var cursorPin: Pin?
        init(_ p: TrekMapView) { parent = p }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tile = overlay as? MKTileOverlay {
                let r = MKTileOverlayRenderer(tileOverlay: tile)
                if tile.urlTemplate?.contains("waymarked") == true { r.alpha = 0.85 }
                return r
            }
            if let line = overlay as? TrackLine {
                let r = MKPolylineRenderer(polyline: line)
                r.lineJoin = .round; r.lineCap = .round
                if line.role == .casing { r.strokeColor = UIColor.white.withAlphaComponent(line.dim ? 0.5 : 0.95); r.lineWidth = 8 }
                else { r.strokeColor = UIColor(Theme.red).withAlphaComponent(line.dim ? 0.45 : 1); r.lineWidth = line.dim ? 3.5 : 4.5 }
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? Pin else { return nil }
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: "pin", for: pin) as! PinView
            v.configure(pin); return v
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let id = (annotation as? Pin)?.trackID { parent.onSelect?(id) }
            mapView.deselectAnnotation(annotation, animated: false)
        }

        /// Tocco vicino a una traccia → la seleziona.
        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let onSelect = parent.onSelect, let map = g.view as? MKMapView else { return }
            let pt = g.location(in: map)
            var best: (UUID, CGFloat)?
            for t in parent.tracks {
                for c in stride(from: 0, to: t.coords.count, by: max(1, t.coords.count / 300)) {
                    let p = map.convert(t.coords[c], toPointTo: map)
                    let d = hypot(p.x - pt.x, p.y - pt.y)
                    if d < 28, d < (best?.1 ?? .infinity) { best = (t.id, d) }
                }
            }
            if let b = best { onSelect(b.0) }
        }
    }
}

final class TrackLine: MKPolyline {
    enum Role { case casing, line }
    var role: Role = .line
    var trackID: UUID?
    var dim = false
}

final class Pin: NSObject, MKAnnotation {
    enum Kind { case start, end, summit, cursor }
    let kind: Kind
    @objc dynamic var coordinate: CLLocationCoordinate2D
    let trackID: UUID?
    let title: String?
    init(kind: Kind, coordinate: CLLocationCoordinate2D, trackID: UUID?, title: String? = nil) {
        self.kind = kind; self.coordinate = coordinate; self.trackID = trackID; self.title = title
    }
}

final class PinView: MKAnnotationView {
    private let label = UILabel()
    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        label.font = .systemFont(ofSize: 12, weight: .heavy)
        label.textColor = .white; label.textAlignment = .center
        label.layer.cornerRadius = 6; label.clipsToBounds = true
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ pin: Pin) {
        annotation = pin
        layer.shadowColor = UIColor.black.cgColor; layer.shadowOpacity = 0.35; layer.shadowRadius = 2; layer.shadowOffset = .init(width: 0, height: 1)
        switch pin.kind {
        case .summit:
            label.isHidden = false; label.text = pin.title; label.backgroundColor = UIColor(white: 0.08, alpha: 0.9)
            let w = (label.text as NSString?)?.size(withAttributes: [.font: label.font!]).width ?? 40
            frame = CGRect(x: 0, y: 0, width: w + 14, height: 22); label.frame = bounds
            backgroundColor = .clear; layer.cornerRadius = 6; layer.borderWidth = 0
            centerOffset = CGPoint(x: 0, y: -18); zPriority = .defaultSelected
        default:
            label.isHidden = true
            let size: CGFloat = pin.kind == .cursor ? 18 : 16
            frame = CGRect(x: 0, y: 0, width: size, height: size); centerOffset = .zero
            layer.cornerRadius = size / 2; layer.borderWidth = 3; layer.borderColor = UIColor.white.cgColor
            backgroundColor = switch pin.kind {
            case .start: UIColor(Theme.startGreen)
            case .end: UIColor(white: 0.1, alpha: 1)
            default: UIColor(Theme.red)
            }
            zPriority = pin.kind == .cursor ? .max : .defaultUnselected
        }
    }
}
