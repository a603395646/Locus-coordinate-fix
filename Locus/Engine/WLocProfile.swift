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

/// Native parser for shared map links. It expands supported short links on-device,
/// then stores all imported coordinates as WGS-84 for consistent Locus handling.
enum WLocMapLinkParser {
    private enum Source {
        case apple
        case amap
        case google
    }

    static func parse(_ raw: String) async throws -> WLocProfile {
        if let direct = parseDirect(raw) { return direct }
        guard let url = extractURL(from: raw),
              let host = url.host?.lowercased(),
              source(for: host) != nil else {
            throw WLocProfileError.unsupportedMapLink
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse,
               !(200..<400).contains(http.statusCode) {
                throw WLocProfileError.mapLinkFetchFailed
            }
            if let finalURL = response.url,
               let profile = parseDirect(finalURL.absoluteString) {
                return profile
            }
            if let body = String(data: data, encoding: .utf8),
               let profile = parseDirect(body) {
                return profile
            }
        } catch let error as WLocProfileError {
            throw error
        } catch {
            throw WLocProfileError.mapLinkFetchFailed
        }

        throw WLocProfileError.unsupportedMapLink
    }

    /// Parses direct URLs and plain coordinate text without network access.
    static func parseDirect(_ raw: String) -> WLocProfile? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let coordinate = parseBareCoordinate(text) {
            return WLocProfile(
                name: "Shared location",
                coordinate: coordinate,
                coordinateReference: "WGS-84"
            )
        }

        guard let url = extractURL(from: text),
              let host = url.host?.lowercased(),
              let source = source(for: host),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let items = components.queryItems ?? []
        func value(_ key: String) -> String? {
            items.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame })?.value
        }

        var coordinate: CLLocationCoordinate2D?
        switch source {
        case .apple:
            coordinate = ["coordinate", "ll", "q"]
                .compactMap { value($0) }
                .compactMap { parsePair($0, longitudeFirst: false) }
                .first
        case .amap:
            coordinate = ["position", "lnglat", "to"]
                .compactMap { value($0) }
                .compactMap { parsePair($0, longitudeFirst: true) }
                .first
            if coordinate == nil, let q = value("q") {
                coordinate = parsePair(q, longitudeFirst: false)
            }
        case .google:
            if let q = value("q") ?? value("query") {
                coordinate = parsePair(q, longitudeFirst: false)
            }
            if coordinate == nil {
                coordinate = parseGooglePath(components.path)
            }
        }

        guard let rawCoordinate = coordinate,
              CLLocationCoordinate2DIsValid(rawCoordinate) else {
            return nil
        }

        let wgs84: CLLocationCoordinate2D
        switch source {
        case .apple, .google:
            // Apple/Google map links use GCJ-02 in mainland China, WGS-84 in HK/Macau/Taiwan.
            wgs84 = ChinaCoordinateTransform.isWithinMainlandCoverage(rawCoordinate)
                ? ChinaCoordinateTransform.gcj02ToWGS84(rawCoordinate)
                : rawCoordinate
        case .amap:
            // Amap's map coordinate system remains GCJ-02 in the nearby special regions.
            wgs84 = ChinaCoordinateTransform.isWithinGCJBounds(rawCoordinate)
                ? ChinaCoordinateTransform.gcj02ToWGS84ForMapSource(rawCoordinate)
                : rawCoordinate
        }

        let suppliedName = value("name")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let qName = value("q").flatMap { parsePair($0, longitudeFirst: false) == nil ? $0 : nil } ?? ""
        let name = suppliedName.isEmpty ? (qName.isEmpty ? "Shared location" : qName) : suppliedName
        let profile = WLocProfile(
            name: name,
            coordinate: wgs84,
            coordinateReference: "WGS-84"
        )
        return profile.isValid ? profile : nil
    }

    private static func source(for host: String) -> Source? {
        if host == "maps.apple.com" || host.hasSuffix(".maps.apple.com") {
            return .apple
        }
        if host == "amap.com" || host.hasSuffix(".amap.com") {
            return .amap
        }
        if host == "goo.gl" || host == "maps.app.goo.gl"
            || host == "google.com" || host.hasSuffix(".google.com") {
            return .google
        }
        return nil
    }

    private static func extractURL(from text: String) -> URL? {
        let pattern = #"https?://[^\s'"<>]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else {
            return nil
        }
        var candidate = String(text[range])
        while let last = candidate.last, "，。；）)]}>,.".contains(last) {
            candidate.removeLast()
        }
        return URL(string: candidate)
    }

    private static func parseBareCoordinate(_ text: String) -> CLLocationCoordinate2D? {
        let pieces = text.replacingOccurrences(of: "，", with: ",")
            .split(separator: ",", omittingEmptySubsequences: true)
        guard pieces.count == 2,
              let latitude = Double(pieces[0].trimmingCharacters(in: .whitespaces)),
              let longitude = Double(pieces[1].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    private static func parsePair(
        _ value: String,
        longitudeFirst: Bool
    ) -> CLLocationCoordinate2D? {
        let pieces = value.split(separator: ",", omittingEmptySubsequences: true)
        guard pieces.count >= 2,
              let first = Double(pieces[0].trimmingCharacters(in: .whitespaces)),
              let second = Double(pieces[1].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        let coordinate = longitudeFirst
            ? CLLocationCoordinate2D(latitude: second, longitude: first)
            : CLLocationCoordinate2D(latitude: first, longitude: second)
        return CLLocationCoordinate2DIsValid(coordinate) ? coordinate : nil
    }

    private static func parseGooglePath(_ path: String) -> CLLocationCoordinate2D? {
        let pattern = #"/@(-?\d{1,3}\.\d+),(-?\d{1,3}\.\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)),
              let latitudeRange = Range(match.range(at: 1), in: path),
              let longitudeRange = Range(match.range(at: 2), in: path),
              let latitude = Double(path[latitudeRange]),
              let longitude = Double(path[longitudeRange]) else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
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
    case unsupportedMapLink
    case mapLinkFetchFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "This is not a supported Locus profile export."
        case .invalidProfiles:
            return "The file contains invalid coordinates or too many profiles."
        case .unsupportedMapLink:
            return "This map link is not supported. Use an Apple Maps, Amap or Google Maps share link."
        case .mapLinkFetchFailed:
            return "Could not expand this map share link. Check the network and try again."
        }
    }
}
