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
    var accuracyMeters: Double
    var randomRadiusMeters: Double

    private enum CodingKeys: String, CodingKey {
        case id, name, latitude, longitude, coordinateReference, createdAt
        case accuracyMeters, randomRadiusMeters
    }

    /// Backward-compatible decoder for profiles created before WLOC metadata was added.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        latitude = try values.decode(Double.self, forKey: .latitude)
        longitude = try values.decode(Double.self, forKey: .longitude)
        coordinateReference = try values.decode(String.self, forKey: .coordinateReference)
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        accuracyMeters = try values.decodeIfPresent(Double.self, forKey: .accuracyMeters) ?? 25
        randomRadiusMeters = try values.decodeIfPresent(Double.self, forKey: .randomRadiusMeters) ?? 0
    }

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
        createdAt: Date = Date(),
        accuracyMeters: Double = 25,
        randomRadiusMeters: Double = 0
    ) {
        self.id = id
        self.name = name
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.coordinateReference = coordinateReference
        self.createdAt = createdAt
        self.accuracyMeters = accuracyMeters
        self.randomRadiusMeters = randomRadiusMeters
    }

    var isValid: Bool {
        let supportedReference = coordinateReference == "WGS-84"
            || (coordinateReference == "GCJ-02"
                && ChinaCoordinateTransform.isWithinMainlandCoverage(coordinate))
        return CLLocationCoordinate2DIsValid(coordinate)
            && latitude.isFinite
            && longitude.isFinite
            && supportedReference
            && accuracyMeters.isFinite
            && (1...10_000).contains(accuracyMeters)
            && randomRadiusMeters.isFinite
            && (0...10_000).contains(randomRadiusMeters)
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

        if let payload = try? decoder.decode(WLocProfileExport.self, from: data) {
            guard payload.schema == exportSchema, payload.version == 1 else {
                throw WLocProfileError.unsupportedFormat
            }
            guard payload.profiles.count <= 500,
                  payload.profiles.allSatisfy(\.isValid) else {
                throw WLocProfileError.invalidProfiles
            }
            return payload.profiles
        }

        // WLOC's exported persistent setting is a single JSON object containing
        // longitude, latitude, accuracy and optional randomRadius.
        // WLOC's picker normalizes map links to WGS-84 before saving this object.
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WLocProfileError.unsupportedFormat
        }
        let settings: [String: Any]
        if let object = root["wloc_settings"] as? [String: Any] {
            settings = object
        } else if let encoded = root["wloc_settings"] as? String,
                  let nestedData = encoded.data(using: .utf8),
                  let nestedObject = try? JSONSerialization.jsonObject(with: nestedData) as? [String: Any] {
            settings = nestedObject
        } else {
            settings = root
        }
        func number(_ key: String) -> Double? {
            if let value = settings[key] as? NSNumber { return value.doubleValue }
            if let value = settings[key] as? String {
                return Double(value.replacingOccurrences(of: ",", with: "."))
            }
            return nil
        }
        guard let latitude = number("latitude"),
              let longitude = number("longitude") else {
            throw WLocProfileError.unsupportedFormat
        }

        let importedName = (settings["name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let profile = WLocProfile(
            name: importedName.isEmpty ? "Imported WLOC" : importedName,
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            coordinateReference: "WGS-84",
            accuracyMeters: number("accuracy") ?? 25,
            randomRadiusMeters: number("randomRadius") ?? 0
        )
        guard profile.isValid else {
            throw WLocProfileError.invalidProfiles
        }
        return [profile]
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
