import CoreLocation
import Foundation

@main
struct MapDatumChecks {
    static func main() {
        let beijingWGS84 = CLLocationCoordinate2D(latitude: 39.908823, longitude: 116.397470)
        let beijingGCJ02 = MapDatumMode.automaticChina.mapCoordinate(fromWGS84: beijingWGS84)

        assert(abs(beijingGCJ02.latitude - 39.910226498) < 0.000001)
        assert(abs(beijingGCJ02.longitude - 116.403713582) < 0.000001)

        let restored = MapDatumMode.automaticChina.deviceCoordinate(fromMapCoordinate: beijingGCJ02)
        assert(abs(restored.latitude - beijingWGS84.latitude) < 0.0000001)
        assert(abs(restored.longitude - beijingWGS84.longitude) < 0.0000001)

        let knownLocations: [(wgs84: CLLocationCoordinate2D, gcj02: CLLocationCoordinate2D)] = [
            // Beijing
            (CLLocationCoordinate2D(latitude: 39.908823, longitude: 116.397470),
             CLLocationCoordinate2D(latitude: 39.910226498, longitude: 116.403713582)),
            // Chongqing
            (CLLocationCoordinate2D(latitude: 29.56301, longitude: 106.55156),
             CLLocationCoordinate2D(latitude: 29.560161356, longitude: 106.555277721)),
            // Chengdu
            (CLLocationCoordinate2D(latitude: 30.5728, longitude: 104.0668),
             CLLocationCoordinate2D(latitude: 30.570346141, longitude: 104.069305477)),
            // Shanghai
            (CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
             CLLocationCoordinate2D(latitude: 31.228457738, longitude: 121.478223059)),
            // Shenzhen
            (CLLocationCoordinate2D(latitude: 22.5431, longitude: 114.0579),
             CLLocationCoordinate2D(latitude: 22.540382814, longitude: 114.063013999))
        ]

        for location in knownLocations {
            let converted = MapDatumMode.automaticChina.mapCoordinate(fromWGS84: location.wgs84)
            assert(abs(converted.latitude - location.gcj02.latitude) < 0.000001)
            assert(abs(converted.longitude - location.gcj02.longitude) < 0.000001)

            let restored = MapDatumMode.automaticChina.deviceCoordinate(fromMapCoordinate: converted)
            assert(abs(restored.latitude - location.wgs84.latitude) < 0.0000001)
            assert(abs(restored.longitude - location.wgs84.longitude) < 0.0000001)
        }

        let london = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
        let londonMap = MapDatumMode.automaticChina.mapCoordinate(fromWGS84: london)
        let londonDevice = MapDatumMode.automaticChina.deviceCoordinate(fromMapCoordinate: london)
        assert(londonMap.latitude == london.latitude)
        assert(londonMap.longitude == london.longitude)
        assert(londonDevice.latitude == london.latitude)
        assert(londonDevice.longitude == london.longitude)

        let unchanged = MapDatumMode.off.mapCoordinate(fromWGS84: beijingWGS84)
        let unchangedDevice = MapDatumMode.off.deviceCoordinate(fromMapCoordinate: beijingGCJ02)
        assert(unchanged.latitude == beijingWGS84.latitude)
        assert(unchanged.longitude == beijingWGS84.longitude)
        assert(unchangedDevice.latitude == beijingGCJ02.latitude)
        assert(unchangedDevice.longitude == beijingGCJ02.longitude)

        print("Map datum checks passed")
    }
}
