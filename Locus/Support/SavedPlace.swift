import CoreLocation
import Foundation

struct SavedPlace: Identifiable, Codable, Equatable {
    var id: String { "\(latitude),\(longitude)" }
    var name: String
    var latitude: Double
    var longitude: Double
    /// The datum used by MapKit when this place was saved. Nil means a legacy entry.
    var coordinateReference: String?

    init(
        name: String,
        latitude: Double,
        longitude: Double,
        coordinateReference: String? = nil
    ) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.coordinateReference = coordinateReference
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Legacy favorites/recents retain their historical map-space behavior.
    /// New entries are converted when the user changes the map datum setting.
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

    static func reference(forMapCoordinate coordinate: CLLocationCoordinate2D, mode: MapDatumMode) -> String {
        mode == .automaticChina && ChinaCoordinateTransform.isWithinMainlandCoverage(coordinate)
            ? "GCJ-02"
            : "WGS-84"
    }

    static func load(key: String) -> [SavedPlace] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([SavedPlace].self, from: data) else {
            return []
        }
        return decoded
    }

    static func save(_ places: [SavedPlace], key: String) {
        if let data = try? JSONEncoder().encode(places) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
