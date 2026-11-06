import CoreLocation
import Foundation

/// A portable, on-device location profile. Coordinates are stored in the map datum
/// that was active when the profile was created; no network service is involved.
struct WLocProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var latitude: Double
    var longitude: Double
    var coordinateReference: String
    var createdAt: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Returns this profile in the coordinate datum currently used by the map.
    /// Profiles retain their original datum so switching map modes cannot shift saved places.
    func mapCoordinate(for mode: MapDatumMode) -> CLLocationCoordinate2D {
        switch coordinateReference {
        case "WGS-84":
            return mode.mapCoordinate(fromWGS84: coordinate)
        case "GCJ-02":
            return mode == .automaticChina
                ? coordinate
                : MapDatumMode.automaticChina.deviceCoordinate(fromMapCoordinate: coordinate)
        default:
            return coordinate
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        coordinate: CLLocationCoordinate2D,
        coordinateReference: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.coordinateReference = coordinateReference
        self.createdAt = createdAt
    }

    var isValid: Bool {
        let supportedReference = coordinateReference == "WGS-84"
            || (coordinateReference == "GCJ-02"
                && ChinaCoordinateTransform.isWithinMainlandCoverage(coordinate))
        return CLLocationCoordinate2DIsValid(coordinate)
            && latitude.isFinite
            && longitude.isFinite
            && supportedReference
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static let storageKey = "locus.wlocProfiles.v1"
    static let exportSchema = "com.chrismack.locus.wloc-profiles"

    static func load() -> [WLocProfile] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let profiles = try? JSONDecoder().decode([WLocProfile].self, from: data) else {
            return []
        }
        return profiles.filter(\.isValid)
    }

    static func save(_ profiles: [WLocProfile]) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func exportJSON(_ profiles: [WLocProfile]) throws -> String {
        let payload = WLocProfileExport(
            schema: exportSchema,
            version: 1,
            exportedAt: Date(),
            profiles: profiles
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        guard let json = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return json
    }

    static func importJSON(_ data: Data) throws -> [WLocProfile] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(WLocProfileExport.self, from: data)
        guard payload.schema == exportSchema, payload.version == 1 else {
            throw WLocProfileError.unsupportedFormat
        }
        guard payload.profiles.count <= 500,
              payload.profiles.allSatisfy(\.isValid) else {
            throw WLocProfileError.invalidProfiles
        }
        return payload.profiles
    }
}

private struct WLocProfileExport: Codable {
    let schema: String
    let version: Int
    let exportedAt: Date
    let profiles: [WLocProfile]
}

enum WLocProfileError: LocalizedError {
    case unsupportedFormat
    case invalidProfiles

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "This is not a supported Locus profile export."
        case .invalidProfiles:
            return "The file contains invalid coordinates or too many profiles."
        }
    }
}
