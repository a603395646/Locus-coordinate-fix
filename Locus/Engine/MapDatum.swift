import CoreLocation
import Foundation

/// Coordinates used by the MapKit canvas in mainland China are treated as GCJ-02.
/// Core Location and Apple's developer location service use WGS-84.
enum MapDatumMode: String, CaseIterable, Identifiable {
    case automaticChina
    case off

    static let defaultsKey = "locus.mapDatumMode"

    static var current: MapDatumMode {
        MapDatumMode(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .automaticChina
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automaticChina:
            return "Automatic (mainland China)"
        case .off:
            return "Off (original coordinates)"
        }
    }

    /// Converts a Core Location WGS-84 fix into the coordinate space used by the map.
    func mapCoordinate(fromWGS84 coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard self == .automaticChina,
              ChinaCoordinateTransform.isWithinMainlandCoverage(coordinate) else {
            return coordinate
        }
        return ChinaCoordinateTransform.wgs84ToGCJ02(coordinate)
    }

    /// Converts a map-space coordinate back to WGS-84 before sending it to iOS.
    func deviceCoordinate(fromMapCoordinate coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard self == .automaticChina,
              ChinaCoordinateTransform.isWithinMainlandCoverage(coordinate) else {
            return coordinate
        }
        return ChinaCoordinateTransform.gcj02ToWGS84(coordinate)
    }
}

enum ChinaCoordinateTransform {
    // Deliberately a coarse coverage rectangle, not an authoritative national border.
    // The automatic mode is intended for ordinary mainland-China use, not border areas.
    static func isWithinMainlandCoverage(_ coordinate: CLLocationCoordinate2D) -> Bool {
        CLLocationCoordinate2DIsValid(coordinate)
            && (72.004...137.8347).contains(coordinate.longitude)
            && (0.8293...55.8271).contains(coordinate.latitude)
    }

    static func wgs84ToGCJ02(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard isWithinMainlandCoverage(coordinate) else { return coordinate }

        let x = coordinate.longitude - 105.0
        let y = coordinate.latitude - 35.0
        let latitudeOffset = transformLatitude(x: x, y: y)
        let longitudeOffset = transformLongitude(x: x, y: y)
        let radians = coordinate.latitude / 180.0 * Double.pi
        let eccentricity = 0.00669342162296594323
        let axis = 6_378_245.0
        let magic = 1.0 - eccentricity * pow(sin(radians), 2.0)
        let rootMagic = sqrt(magic)

        let latitudeDelta = latitudeOffset * 180.0
            / ((axis * (1.0 - eccentricity)) / (magic * rootMagic) * Double.pi)
        let longitudeDelta = longitudeOffset * 180.0
            / (axis / rootMagic * cos(radians) * Double.pi)

        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + latitudeDelta,
            longitude: coordinate.longitude + longitudeDelta
        )
    }

    /// Iterative inverse of WGS-84 → GCJ-02. This avoids applying a fixed offset,
    /// which is inaccurate because the GCJ-02 displacement varies by location.
    static func gcj02ToWGS84(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard isWithinMainlandCoverage(coordinate) else { return coordinate }

        var estimate = coordinate
        for _ in 0..<10 {
            let converted = wgs84ToGCJ02(estimate)
            let latitudeError = converted.latitude - coordinate.latitude
            let longitudeError = converted.longitude - coordinate.longitude
            estimate.latitude -= latitudeError
            estimate.longitude -= longitudeError

            if max(abs(latitudeError), abs(longitudeError)) < 1e-9 {
                break
            }
        }
        return estimate
    }

    private static func transformLatitude(x: Double, y: Double) -> Double {
        var result = -100.0 + 2.0 * x + 3.0 * y
            + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
        result += (20.0 * sin(6.0 * x * Double.pi) + 20.0 * sin(2.0 * x * Double.pi)) * 2.0 / 3.0
        result += (20.0 * sin(y * Double.pi) + 40.0 * sin(y / 3.0 * Double.pi)) * 2.0 / 3.0
        result += (160.0 * sin(y / 12.0 * Double.pi) + 320.0 * sin(y * Double.pi / 30.0)) * 2.0 / 3.0
        return result
    }

    private static func transformLongitude(x: Double, y: Double) -> Double {
        var result = 300.0 + x + 2.0 * y
            + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
        result += (20.0 * sin(6.0 * x * Double.pi) + 20.0 * sin(2.0 * x * Double.pi)) * 2.0 / 3.0
        result += (20.0 * sin(x * Double.pi) + 40.0 * sin(x / 3.0 * Double.pi)) * 2.0 / 3.0
        result += (150.0 * sin(x / 12.0 * Double.pi) + 300.0 * sin(x / 30.0 * Double.pi)) * 2.0 / 3.0
        return result
    }
}
