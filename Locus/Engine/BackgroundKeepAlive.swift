import CoreLocation
import Foundation

struct LocationFixSnapshot {
    let latitude: Double
    let longitude: Double
    let altitude: CLLocationDistance
    let horizontalAccuracy: CLLocationAccuracy
    let verticalAccuracy: CLLocationAccuracy
    let speed: CLLocationSpeed
    let course: CLLocationDirection
    let timestamp: Date
    let isSimulatedBySoftware: Bool?
    let isProducedByAccessory: Bool?
    let authorization: String
    let accuracyAuthorization: String
}

final class BackgroundKeepAlive: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var lastKnownCoordinate: CLLocationCoordinate2D?
    var onCoordinateUpdate: (@MainActor (CLLocationCoordinate2D) -> Void)?
    var onDiagnosticsUpdate: (@MainActor (LocationFixSnapshot) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = false
    }

    func start() {
        manager.requestAlwaysAuthorization()
        manager.startUpdatingLocation()
    }

    func stop() {
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last else { return }

        // Keep a diagnostic snapshot even when the fix is stale or low accuracy.
        // The accepted coordinate below retains the existing quality filter.
        let source = fix.sourceInformation
        let snapshot = LocationFixSnapshot(
            latitude: fix.coordinate.latitude,
            longitude: fix.coordinate.longitude,
            altitude: fix.altitude,
            horizontalAccuracy: fix.horizontalAccuracy,
            verticalAccuracy: fix.verticalAccuracy,
            speed: fix.speed,
            course: fix.course,
            timestamp: fix.timestamp,
            isSimulatedBySoftware: source?.isSimulatedBySoftware,
            isProducedByAccessory: source?.isProducedByAccessory,
            authorization: Self.authorizationName(manager.authorizationStatus),
            accuracyAuthorization: Self.accuracyAuthorizationName(manager.accuracyAuthorization)
        )
        Task { @MainActor [weak self] in
            self?.onDiagnosticsUpdate?(snapshot)
        }

        guard fix.horizontalAccuracy >= 0,
              fix.horizontalAccuracy <= 100,
              abs(fix.timestamp.timeIntervalSinceNow) <= 30 else { return }
        lastKnownCoordinate = fix.coordinate
        let coordinate = fix.coordinate
        Task { @MainActor [weak self] in
            self?.onCoordinateUpdate?(coordinate)
        }
    }

    private static func authorizationName(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return LocusLocalization.string("Not determined")
        case .restricted: return LocusLocalization.string("Restricted")
        case .denied: return LocusLocalization.string("Denied")
        case .authorizedAlways: return LocusLocalization.string("Always")
        case .authorizedWhenInUse: return LocusLocalization.string("While using")
        @unknown default: return LocusLocalization.string("Unknown")
        }
    }

    private static func accuracyAuthorizationName(_ status: CLAccuracyAuthorization) -> String {
        switch status {
        case .fullAccuracy: return LocusLocalization.string("Full accuracy")
        case .reducedAccuracy: return LocusLocalization.string("Reduced accuracy")
        @unknown default: return "Unknown"
        }
    }
}
