import Foundation
import SwiftData
import CoreLocation

/// Un punto della traccia: lat, lon, quota (m), istante.
struct TrackPoint: Codable, Hashable {
    var lat: Double
    var lon: Double
    var ele: Double?
    var time: Date?

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    var location: CLLocation { CLLocation(latitude: lat, longitude: lon) }
}

enum Difficulty: String, Codable, CaseIterable, Identifiable {
    case T, E, EE, EEA
    var id: String { rawValue }
    var name: String {
        switch self {
        case .T: "Turistico"
        case .E: "Escursionistico"
        case .EE: "Escursionisti esperti"
        case .EEA: "Esperti con attrezzatura"
        }
    }
    var short: String {
        switch self {
        case .T: "Turistico"
        case .E: "Escurs."
        case .EE: "Esperti"
        case .EEA: "Attrezz."
        }
    }
}

enum TrekSource: String, Codable {
    case health, gpx, recorded, manual, example
}

@Model
final class Trek {
    @Attribute(.unique) var id: UUID
    var name: String
    var location: String
    var region: String
    var date: Date
    var difficultyRaw: String
    var rating: Int
    var notes: String
    var companions: String
    var distance: Double      // metri
    var gain: Double          // metri
    var loss: Double
    var maxEle: Double?
    var minEle: Double?
    var duration: Double      // secondi, con soste
    var moving: Double        // secondi in movimento
    var sourceRaw: String
    var healthWorkoutID: UUID?
    var fileName: String?
    @Attribute(.externalStorage) var trackData: Data?
    @Relationship(deleteRule: .cascade, inverse: \TrekPhoto.trek) var photos: [TrekPhoto] = []
    var createdAt: Date

    init(id: UUID = UUID(), name: String = "", location: String = "", region: String = "", date: Date = .now,
         difficulty: Difficulty = .E, rating: Int = 0, notes: String = "", companions: String = "",
         distance: Double = 0, gain: Double = 0, loss: Double = 0, maxEle: Double? = nil, minEle: Double? = nil,
         duration: Double = 0, moving: Double = 0, source: TrekSource = .manual, healthWorkoutID: UUID? = nil,
         fileName: String? = nil, track: [TrackPoint] = []) {
        self.id = id; self.name = name; self.location = location; self.region = region; self.date = date
        self.difficultyRaw = difficulty.rawValue; self.rating = rating; self.notes = notes; self.companions = companions
        self.distance = distance; self.gain = gain; self.loss = loss; self.maxEle = maxEle; self.minEle = minEle
        self.duration = duration; self.moving = moving; self.sourceRaw = source.rawValue
        self.healthWorkoutID = healthWorkoutID; self.fileName = fileName; self.createdAt = .now
        self.trackData = track.isEmpty ? nil : try? JSONEncoder().encode(track)
    }

    var difficulty: Difficulty {
        get { Difficulty(rawValue: difficultyRaw) ?? .E }
        set { difficultyRaw = newValue.rawValue }
    }
    var source: TrekSource { TrekSource(rawValue: sourceRaw) ?? .manual }
    var isExample: Bool { source == .example }

    /// Decodifica pigra della traccia (cache in memoria).
    @Transient private var _track: [TrackPoint]? = nil
    var track: [TrackPoint] {
        get {
            if let t = _track { return t }
            let t = trackData.flatMap { try? JSONDecoder().decode([TrackPoint].self, from: $0) } ?? []
            _track = t; return t
        }
        set { _track = newValue; trackData = newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue) }
    }
    var hasTrack: Bool { trackData != nil && track.count > 1 }
    var placeLine: String { [location, region].filter { !$0.isEmpty }.joined(separator: " · ") }
    var timeInMotion: Double { moving > 0 ? moving : duration }

    func apply(_ s: TrackStats) {
        distance = s.distance; gain = s.gain; loss = s.loss; maxEle = s.maxEle; minEle = s.minEle
        if s.duration > 0 { duration = s.duration }
        if s.moving > 0 { moving = s.moving }
    }
}

@Model
final class TrekPhoto {
    var id: UUID
    @Attribute(.externalStorage) var data: Data
    var order: Int
    var trek: Trek?
    init(data: Data, order: Int) { self.id = UUID(); self.data = data; self.order = order }
}
