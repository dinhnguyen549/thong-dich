import Foundation
import Observation

// MARK: - Transcript data

/// One line on screen: what was said, and its Vietnamese translation.
struct TranscriptLine: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case speech, liturgy, prayer }
    enum Status: String, Codable, Sendable { case waiting, translating, done, failed }

    var id = UUID()
    var source: String
    var language: SpokenLanguage
    var vietnamese: String = ""
    var kind: Kind = .speech
    var title: String? = nil            // prayer name
    var status: Status = .waiting
    var offset: TimeInterval = 0        // seconds from the start of the session / recording
    var date: Date = Date()             // wall-clock time the line was heard
}

/// A place the user has named ("St. Joseph Church"). Matched by GPS on the device only.
struct SavedPlace: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var latitude: Double?               // nil for places named by hand without GPS
    var longitude: Double?
    var radius: Double = 250            // metres

    func distance(toLatitude lat: Double, longitude lon: Double) -> Double {
        guard let latitude, let longitude else { return .greatestFiniteMagnitude }
        // Haversine distance in metres
        let r = 6_371_000.0
        let dLat = (lat - latitude) * .pi / 180
        let dLon = (lon - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(latitude * .pi / 180) * cos(lat * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// A saved session (live listening or a translated recording).
struct SessionRecord: Codable, Identifiable, Sendable {
    enum Source: String, Codable, Sendable { case live, recording }

    var id = UUID()
    var source: Source
    var fileName: String? = nil
    var mode: TranslationMode
    var startedAt: Date
    var endedAt: Date
    var placeID: UUID? = nil
    var placeName: String? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    var lines: [TranscriptLine] = []

    var summary: SessionSummary {
        SessionSummary(
            id: id, source: source, fileName: fileName, mode: mode, startedAt: startedAt, endedAt: endedAt,
            placeID: placeID, placeName: placeName, latitude: latitude, longitude: longitude,
            lineCount: lines.count,
            preview: lines.first(where: { !$0.vietnamese.isEmpty })?.vietnamese ?? lines.first?.source ?? "")
    }
}

/// Small index entry so the History list opens instantly even with hundreds of sessions.
struct SessionSummary: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var source: SessionRecord.Source
    var fileName: String?
    var mode: TranslationMode
    var startedAt: Date
    var endedAt: Date
    var placeID: UUID?
    var placeName: String?
    var latitude: Double?
    var longitude: Double?
    var lineCount: Int
    var preview: String

    var hasCoordinates: Bool { latitude != nil && longitude != nil }
}

// MARK: - Store

/// Saves history on the device (Application Support/History). Never leaves the iPhone.
@MainActor
@Observable
final class HistoryStore {
    private(set) var summaries: [SessionSummary] = []
    private(set) var places: [SavedPlace] = []

    private let folder: URL
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = support.appendingPathComponent("History", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        ModelLibrary.excludeFromBackup(folder)
        load()
    }

    private var indexURL: URL { folder.appendingPathComponent("index.json") }
    private var placesURL: URL { folder.appendingPathComponent("places.json") }
    private func recordURL(_ id: UUID) -> URL { folder.appendingPathComponent("\(id.uuidString).json") }

    private func load() {
        if let data = try? Data(contentsOf: indexURL),
           let list = try? decoder.decode([SessionSummary].self, from: data) {
            summaries = list.sorted { $0.startedAt > $1.startedAt }
        }
        if let data = try? Data(contentsOf: placesURL),
           let list = try? decoder.decode([SavedPlace].self, from: data) {
            places = list
        }
    }

    private func writeIndex() {
        if let data = try? encoder.encode(summaries) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    private func writePlaces() {
        if let data = try? encoder.encode(places) {
            try? data.write(to: placesURL, options: .atomic)
        }
    }

    // MARK: Sessions

    func save(_ record: SessionRecord) {
        guard !record.lines.isEmpty else { return }
        if let data = try? encoder.encode(record) {
            try? data.write(to: recordURL(record.id), options: .atomic)
        }
        let summary = record.summary
        if let i = summaries.firstIndex(where: { $0.id == record.id }) {
            summaries[i] = summary
        } else {
            summaries.insert(summary, at: 0)
        }
        summaries.sort { $0.startedAt > $1.startedAt }
        writeIndex()
    }

    func record(_ id: UUID) -> SessionRecord? {
        guard let data = try? Data(contentsOf: recordURL(id)) else { return nil }
        return try? decoder.decode(SessionRecord.self, from: data)
    }

    func delete(_ ids: [UUID]) {
        let set = Set(ids)
        for id in ids { try? FileManager.default.removeItem(at: recordURL(id)) }
        summaries.removeAll { set.contains($0.id) }
        writeIndex()
    }

    func deleteAll() {
        for s in summaries { try? FileManager.default.removeItem(at: recordURL(s.id)) }
        summaries.removeAll()
        writeIndex()
    }

    // MARK: Places

    /// The saved place covering these coordinates, if any.
    func place(near latitude: Double, _ longitude: Double) -> SavedPlace? {
        places
            .map { ($0, $0.distance(toLatitude: latitude, longitude: longitude)) }
            .filter { $0.1 <= $0.0.radius }
            .min { $0.1 < $1.1 }?.0
    }

    /// Creates a named place at the given coordinates and labels every unnamed session recorded there.
    @discardableResult
    func addPlace(named name: String, latitude: Double, longitude: Double) -> SavedPlace {
        let place = SavedPlace(name: name.trimmingCharacters(in: .whitespaces), latitude: latitude, longitude: longitude)
        places.append(place)
        writePlaces()
        let matching = summaries.filter { s in
            guard s.placeID == nil, let lat = s.latitude, let lon = s.longitude else { return false }
            return place.distance(toLatitude: lat, longitude: lon) <= place.radius
        }
        assign(matching.map(\.id), to: place)
        return place
    }

    /// Creates a place with no coordinates (manual label only).
    @discardableResult
    func addManualPlace(named name: String) -> SavedPlace {
        let place = SavedPlace(name: name.trimmingCharacters(in: .whitespaces), latitude: nil, longitude: nil, radius: 0)
        places.append(place)
        writePlaces()
        return place
    }

    func renamePlace(_ id: UUID, to name: String) {
        guard let i = places.firstIndex(where: { $0.id == id }) else { return }
        places[i].name = name
        writePlaces()
        let affected = summaries.filter { $0.placeID == id }.map(\.id)
        updateRecords(affected) { $0.placeName = name }
    }

    func deletePlace(_ id: UUID) {
        places.removeAll { $0.id == id }
        writePlaces()
        let affected = summaries.filter { $0.placeID == id }.map(\.id)
        updateRecords(affected) { $0.placeID = nil; $0.placeName = nil }
    }

    /// Moves sessions to a place (or to "no place" when nil).
    func assign(_ ids: [UUID], to place: SavedPlace?) {
        updateRecords(ids) {
            $0.placeID = place?.id
            $0.placeName = place?.name
        }
    }

    private func updateRecords(_ ids: [UUID], _ change: (inout SessionRecord) -> Void) {
        for id in ids {
            guard var record = record(id) else { continue }
            change(&record)
            if let data = try? encoder.encode(record) {
                try? data.write(to: recordURL(id), options: .atomic)
            }
            if let i = summaries.firstIndex(where: { $0.id == id }) {
                summaries[i] = record.summary
            }
        }
        writeIndex()
    }

    // MARK: Export

    static func exportText(_ record: SessionRecord, language: AppLanguage) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: language == .vietnamese ? "vi_VN" : "en_US")
        df.dateStyle = .full
        df.timeStyle = .short
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm:ss"

        var out = "Thông Dịch — \(L.modeName(record.mode))\n"
        out += df.string(from: record.startedAt)
        if let place = record.placeName { out += " · \(place)" }
        if let file = record.fileName { out += "\n\(file)" }
        out += "\n\n"
        for line in record.lines {
            let stamp = record.source == .recording ? formatOffset(line.offset) : tf.string(from: line.date)
            if line.kind == .prayer, let title = line.title {
                out += "[\(stamp)] ✝ \(title)\n"
                if !line.vietnamese.isEmpty { out += "    \(line.vietnamese)\n" }
                out += "\n"
                continue
            }
            out += "[\(stamp)] \(line.language.badge): \(line.source)\n"
            out += "           VI: \(line.vietnamese)\n\n"
        }
        return out
    }

    static func formatOffset(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%02d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
    }
}
