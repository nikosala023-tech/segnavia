import Foundation
import HealthKit
import CoreLocation

/// Un allenamento di Salute che potrebbe diventare un trekking.
struct HealthCandidate: Identifiable, Hashable {
    let id: UUID
    let workout: HKWorkout
    let start: Date
    let end: Date
    let distance: Double       // m
    let ascent: Double?        // m, se l'ha salvato il dispositivo
    let isHiking: Bool
    let sourceName: String

    var duration: TimeInterval { end.timeIntervalSince(start) }
    /// Euristica: escursionismo dichiarato, oppure camminata lunga con dislivello.
    var looksLikeTrek: Bool { isHiking || ((ascent ?? 0) >= 200 && distance >= 3000) }
}

final class HealthService {
    static let shared = HealthService()
    let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAuthorization() async throws {
        let read: Set<HKObjectType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        try await store.requestAuthorization(toShare: [], read: read)
    }

    /// Allenamenti di escursionismo e camminata, dal più recente.
    func candidates(since: Date) async throws -> [HealthCandidate] {
        let datePred = HKQuery.predicateForSamples(withStart: since, end: nil)
        let typePred = NSCompoundPredicate(orPredicateWithSubpredicates: [
            HKQuery.predicateForWorkouts(with: .hiking),
            HKQuery.predicateForWorkouts(with: .walking),
        ])
        let pred = NSCompoundPredicate(andPredicateWithSubpredicates: [datePred, typePred])
        let workouts: [HKWorkout] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: pred, limit: 1000,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]) { _, samples, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: (samples as? [HKWorkout]) ?? []) }
            }
            store.execute(q)
        }
        return workouts.map { w in
            let distType = HKQuantityType(.distanceWalkingRunning)
            let dist = w.statistics(for: distType)?.sumQuantity()?.doubleValue(for: .meter()) ?? 0
            let ascent = (w.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter())
            return HealthCandidate(id: w.uuid, workout: w, start: w.startDate, end: w.endDate, distance: dist, ascent: ascent,
                                   isHiking: w.workoutActivityType == .hiking, sourceName: w.sourceRevision.source.name)
        }
    }

    /// Percorso GPS dell'allenamento (vuoto se non è stato registrato).
    func route(for workout: HKWorkout) async throws -> [TrackPoint] {
        let routes: [HKWorkoutRoute] = try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: HKSeriesType.workoutRoute(), predicate: HKQuery.predicateForObjects(from: workout),
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: (samples as? [HKWorkoutRoute]) ?? []) }
            }
            store.execute(q)
        }
        var points: [TrackPoint] = []
        for r in routes {
            let locs = try await locations(for: r)
            points += locs.filter { $0.horizontalAccuracy >= 0 && $0.horizontalAccuracy < 60 }.map {
                TrackPoint(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude,
                           ele: $0.verticalAccuracy >= 0 ? $0.altitude : nil, time: $0.timestamp)
            }
        }
        return points.sorted { ($0.time ?? .distantPast) < ($1.time ?? .distantPast) }
    }

    private func locations(for route: HKWorkoutRoute) async throws -> [CLLocation] {
        try await withCheckedThrowingContinuation { cont in
            var all: [CLLocation] = []
            var finished = false
            let q = HKWorkoutRouteQuery(route: route) { _, locs, done, error in
                guard !finished else { return }
                if let error { finished = true; cont.resume(throwing: error); return }
                all.append(contentsOf: locs ?? [])
                if done { finished = true; cont.resume(returning: all) }
            }
            store.execute(q)
        }
    }
}
