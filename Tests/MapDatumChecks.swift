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

        // Apple Maps coordinates in Hong Kong, Macau and Taiwan are already WGS-84.
        // The mainland-only GCJ-02 transform must leave these representative locations intact.
        let appleWGS84Regions: [(name: String, coordinate: CLLocationCoordinate2D)] = [
            ("Hong Kong", CLLocationCoordinate2D(latitude: 22.284774, longitude: 114.159437)),
            ("Macau", CLLocationCoordinate2D(latitude: 22.148148, longitude: 113.555399)),
            ("Taipei", CLLocationCoordinate2D(latitude: 25.033626, longitude: 121.564215))
        ]

        for region in appleWGS84Regions {
            assert(
                !ChinaCoordinateTransform.isWithinMainlandCoverage(region.coordinate),
                "\(region.name) must not be treated as mainland GCJ-02"
            )
            let mapCoordinate = MapDatumMode.automaticChina.mapCoordinate(fromWGS84: region.coordinate)
            let deviceCoordinate = MapDatumMode.automaticChina.deviceCoordinate(fromMapCoordinate: region.coordinate)
            assert(mapCoordinate.latitude == region.coordinate.latitude)
            assert(mapCoordinate.longitude == region.coordinate.longitude)
            assert(deviceCoordinate.latitude == region.coordinate.latitude)
            assert(deviceCoordinate.longitude == region.coordinate.longitude)
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

        // WLOC-compatible local profile export/import round-trip.
        let profile = WLocProfile(
            name: "Chongqing test",
            coordinate: CLLocationCoordinate2D(latitude: 29.56301, longitude: 106.55156),
            coordinateReference: "GCJ-02"
        )
        assert(profile.isValid)
        let exported = try! WLocProfile.exportJSON([profile])
        let imported = try! WLocProfile.importJSON(Data(exported.utf8))
        assert(imported.count == 1)
        assert(imported[0].id == profile.id)
        assert(imported[0].name == profile.name)
        assert(imported[0].coordinateReference == profile.coordinateReference)
        assert(abs(imported[0].latitude - profile.latitude) < 1e-10)
        assert(abs(imported[0].longitude - profile.longitude) < 1e-10)

        // A saved profile must be converted when the map datum changes later.
        let chongqingWGS84 = CLLocationCoordinate2D(latitude: 29.56301, longitude: 106.55156)
        let chongqingGCJ02 = MapDatumMode.automaticChina.mapCoordinate(fromWGS84: chongqingWGS84)
        let wgsProfile = WLocProfile(
            name: "WGS profile",
            coordinate: chongqingWGS84,
            coordinateReference: "WGS-84"
        )
        let gcjProfile = WLocProfile(
            name: "GCJ profile",
            coordinate: chongqingGCJ02,
            coordinateReference: "GCJ-02"
        )
        let wgsProfileOnChinaMap = wgsProfile.mapCoordinate(for: .automaticChina)
        assert(abs(wgsProfileOnChinaMap.latitude - chongqingGCJ02.latitude) < 0.000001)
        assert(abs(wgsProfileOnChinaMap.longitude - chongqingGCJ02.longitude) < 0.000001)

        let gcjProfileOnOriginalMap = gcjProfile.mapCoordinate(for: .off)
        assert(abs(gcjProfileOnOriginalMap.latitude - chongqingWGS84.latitude) < 0.0000001)
        assert(abs(gcjProfileOnOriginalMap.longitude - chongqingWGS84.longitude) < 0.0000001)

        let invalidGCJProfile = WLocProfile(
            name: "Invalid Hong Kong GCJ profile",
            coordinate: CLLocationCoordinate2D(latitude: 22.284774, longitude: 114.159437),
            coordinateReference: "GCJ-02"
        )
        assert(!invalidGCJProfile.isValid)

        // Import a WLOC persistent-settings object without needing proxy storage access.
        let wlocSettingsJSON = """
        {
          "longitude": 106.55156,
          "latitude": 29.56301,
          "accuracy": 25,
          "randomRadius": 40
        }
        """
        let importedWLoc = try! WLocProfile.importJSON(Data(wlocSettingsJSON.utf8))
        assert(importedWLoc.count == 1)
        assert(importedWLoc[0].coordinateReference == "WGS-84")
        assert(abs(importedWLoc[0].latitude - 29.56301) < 1e-10)
        assert(abs(importedWLoc[0].longitude - 106.55156) < 1e-10)
        assert(importedWLoc[0].accuracyMeters == 25)
        assert(importedWLoc[0].randomRadiusMeters == 40)

        // Older profile exports without WLOC metadata remain readable.
        let legacyProfileJSON = """
        [{
          "id": "00000000-0000-0000-0000-000000000001",
          "name": "Legacy profile",
          "latitude": 29.56301,
          "longitude": 106.55156,
          "coordinateReference": "GCJ-02",
          "createdAt": "2026-11-06T05:00:00Z"
        }]
        """
        let legacyProfiles = try! JSONDecoder().decode([WLocProfile].self, from: Data(legacyProfileJSON.utf8))
        assert(legacyProfiles.count == 1)
        assert(legacyProfiles[0].accuracyMeters == 25)
        assert(legacyProfiles[0].randomRadiusMeters == 0)

        print("Map datum and WLOC profile checks passed")
    }
}
