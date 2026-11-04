import CoreLocation
import Foundation

final class BackgroundKeepAlive: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var lastKnownCoordinate: CLLocationCoordinate2D?
    var onCoordinateUpdate: (@MainActor (CLLocationCoordinate2D) -> Void)?

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
        guard let fix = locations.last,
              fix.horizontalAccuracy >= 0,
              fix.horizontalAccuracy <= 100,
              abs(fix.timestamp.timeIntervalSinceNow) <= 30 else { return }
        lastKnownCoordinate = fix.coordinate
        let coordinate = fix.coordinate
        Task { @MainActor [weak self] in
            self?.onCoordinateUpdate?(coordinate)
        }
    }
}
