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

        let chengdu = CLLocationCoordinate2D(latitude: 30.5728, longitude: 104.0668)
        let chengduMap = MapDatumMode.automaticChina.mapCoordinate(fromWGS84: chengdu)
        let chengduRestored = MapDatumMode.automaticChina.deviceCoordinate(fromMapCoordinate: chengduMap)
        assert(abs(chengduRestored.latitude - chengdu.latitude) < 0.0000001)
        assert(abs(chengduRestored.longitude - chengdu.longitude) < 0.0000001)

        let london = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
        let londonMap = MapDatumMode.automaticChina.mapCoordinate(fromWGS84: london)
        assert(londonMap.latitude == london.latitude)
        assert(londonMap.longitude == london.longitude)

        let unchanged = MapDatumMode.off.mapCoordinate(fromWGS84: beijingWGS84)
        assert(unchanged.latitude == beijingWGS84.latitude)
        assert(unchanged.longitude == beijingWGS84.longitude)

        print("Map datum checks passed")
    }
}
