import Foundation
import CoreLocation
import Observation

/// Registra la traccia GPS, anche con schermo spento (modalità background "location").
@Observable
final class Recorder: NSObject, CLLocationManagerDelegate {
    enum State { case idle, running, paused }

    private(set) var state: State = .idle
    private(set) var points: [TrackPoint] = []
    private(set) var accuracy: Double?
    private(set) var authDenied = false
    private var started: Date?
    private var accumulated: TimeInterval = 0
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
    }

    var elapsed: TimeInterval { accumulated + (state == .running ? Date().timeIntervalSince(started ?? .now) : 0) }
    var stats: TrackStats { TrackStats(points) }

    func start() {
        points = []; accumulated = 0; resume()
    }
    func resume() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        started = .now; state = .running
        manager.startUpdatingLocation()
    }
    func pause() {
        accumulated += Date().timeIntervalSince(started ?? .now); state = .paused
        manager.stopUpdatingLocation()
    }
    func finish() -> (points: [TrackPoint], moving: TimeInterval) {
        if state == .running { pause() }
        let r = (points, accumulated)
        reset(); return r
    }
    func reset() { state = .idle; points = []; accumulated = 0; manager.stopUpdatingLocation() }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard state == .running else { return }
        for l in locations where l.horizontalAccuracy >= 0 {
            accuracy = l.horizontalAccuracy
            guard l.horizontalAccuracy <= 40 else { continue }
            let p = TrackPoint(lat: l.coordinate.latitude, lon: l.coordinate.longitude,
                               ele: l.verticalAccuracy >= 0 ? l.altitude : nil, time: l.timestamp)
            if let last = points.last, last.location.distance(from: l) < max(4, l.horizontalAccuracy / 3) { continue }
            points.append(p)
        }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authDenied = [.denied, .restricted].contains(manager.authorizationStatus)
    }
}
