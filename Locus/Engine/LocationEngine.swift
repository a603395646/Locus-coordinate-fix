import CoreLocation
import Darwin
import Foundation
import idevice

enum LocationEngineError: LocalizedError {
    case invalidIP
    case pairingRead(String?)
    case tunnelCreate(String?)
    case remoteServer(String?)
    case simulationCreate(String?)
    case locationSet(String?)
    case invalidCoordinate
    case locationClear(String?)
    case notActive

    var errorDescription: String? {
        switch self {
        case .invalidIP:
            return LocusLocalization.string("Device IP is invalid. Check Settings → Device IP (usually 10.7.0.1).")
        case .pairingRead(let detail):
            return detail ?? LocusLocalization.string("Could not read the required pairing record.")
        case .tunnelCreate(let detail):
            return detail ?? LocusLocalization.string("Could not open the Apple developer tunnel. Check LocalDevVPN and the pairing record.")
        case .remoteServer(let detail):
            return detail ?? LocusLocalization.string("The developer tunnel opened, but the RemoteXPC handshake failed.")
        case .simulationCreate(let detail):
            return detail ?? LocusLocalization.string("Could not open Apple’s location simulation service.")
        case .locationSet(let detail):
            return detail ?? LocusLocalization.string("Failed to set simulated coordinates.")
        case .invalidCoordinate:
            return LocusLocalization.string("The selected map coordinate is invalid.")
        case .locationClear(let detail):
            return detail ?? LocusLocalization.string("Failed to clear simulated location.")
        case .notActive:
            return LocusLocalization.string("No active simulation session.")
        }
    }

    static func from(code: Int32, detail: String?) -> LocationEngineError {
        switch code {
        case 1: return .invalidIP
        case 2: return .pairingRead(detail)
        case 3: return .tunnelCreate(detail)
        case 9: return .remoteServer(detail)
        case 10: return .simulationCreate(detail)
        case 11: return .locationSet(detail)
        case 12: return .locationClear(detail)
        default: return .locationSet(detail)
        }
    }
}

/// Thin Swift wrapper around idevice's DVT location simulation.
///
/// iOS 18–26.3 uses CoreDeviceProxy over LocalDevVPN with a classic lockdown
/// pairing record. Starting with iOS 26.4, lockdownd no longer accepts that
/// loopback route, so newer systems retain the RPPairing path.
enum LocationEngine {
    private static let queue = DispatchQueue(label: "com.chrismack.locus.location", qos: .userInitiated)

    private static var adapter: OpaquePointer?
    private static var handshake: OpaquePointer?
    private static var remoteServer: OpaquePointer?
    private static var locationSimulation: OpaquePointer?
    private static var lockdownHeartbeat: LockdownHeartbeat?
    private static var lastFailureDetail: String?

    private static let ok: Int32 = 0
    private static let invalidIP: Int32 = 1
    private static let pairingRead: Int32 = 2
    private static let tunnelCreate: Int32 = 3
    private static let remoteServerCode: Int32 = 9
    private static let simulationCreate: Int32 = 10
    private static let locationSet: Int32 = 11
    private static let locationClear: Int32 = 12

    private static let lockdownPairingFileName = "lockdown_pair_record.plist"

    static var isSessionActive: Bool { locationSimulation != nil }

    static func set(latitude: Double, longitude: Double, pairingPath: String, deviceIP: String) -> Result<Void, LocationEngineError> {
        let mapCoordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(mapCoordinate) else { return .failure(.invalidCoordinate) }
        let deviceCoordinate = MapDatumMode.current.deviceCoordinate(fromMapCoordinate: mapCoordinate)
        var result: Result<Void, LocationEngineError> = .failure(.locationSet(nil))
        queue.sync {
            lastFailureDetail = nil
            let code = setLocked(
                latitude: deviceCoordinate.latitude,
                longitude: deviceCoordinate.longitude,
                pairingPath: pairingPath,
                deviceIP: deviceIP
            )
            result = code == ok ? .success(()) : .failure(.from(code: code, detail: lastFailureDetail))
        }
        return result
    }

    static func clear() -> Result<Void, LocationEngineError> {
        var result: Result<Void, LocationEngineError> = .failure(.notActive)
        queue.sync {
            lastFailureDetail = nil
            let code = clearLocked()
            result = code == ok ? .success(()) : .failure(.from(code: code, detail: lastFailureDetail))
        }
        return result
    }

    private static var lockdownPairingPath: String {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pairing", isDirectory: true)
        return directory.appendingPathComponent(lockdownPairingFileName).path
    }

    private static func shouldUseCoreDeviceProxy() -> Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return version.majorVersion < 26 || (version.majorVersion == 26 && version.minorVersion < 4)
    }

    private static func consumeError(
        _ error: UnsafeMutablePointer<IdeviceFfiError>?,
        fallback: String
    ) -> String? {
        guard let error else { return nil }
        let code = error.pointee.code
        let subCode = error.pointee.sub_code
        let message = error.pointee.message.flatMap { String(validatingUTF8: $0) } ?? fallback
        idevice_error_free(error)
        return "\(fallback) (idevice code=\(code), sub=\(subCode)): \(message)"
    }

    private static func cleanup() {
        if let locationSimulation {
            location_simulation_free(locationSimulation)
            self.locationSimulation = nil
        }
        if let remoteServer {
            remote_server_free(remoteServer)
            self.remoteServer = nil
        }
        if let handshake {
            rsd_handshake_free(handshake)
            self.handshake = nil
        }
        if let adapter {
            adapter_free(adapter)
            self.adapter = nil
        }
        lockdownHeartbeat?.stop()
        lockdownHeartbeat = nil
    }

    private static func setLocked(
        latitude: Double,
        longitude: Double,
        pairingPath: String,
        deviceIP: String
    ) -> Int32 {
        if let locationSimulation {
            if let error = location_simulation_set(locationSimulation, latitude, longitude) {
                lastFailureDetail = consumeError(error, fallback: "location_simulation_set failed")
                cleanup()
            } else {
                return ok
            }
        }

        let tunnelCode = shouldUseCoreDeviceProxy()
            ? openCoreDeviceProxyTunnel(deviceIP: deviceIP)
            : openRemotePairingTunnel(pairingPath: pairingPath, deviceIP: deviceIP)
        guard tunnelCode == ok else { return tunnelCode }

        if let error = remote_server_connect_rsd(adapter, handshake, &remoteServer) {
            lastFailureDetail = consumeError(error, fallback: "remote_server_connect_rsd failed")
            cleanup()
            return remoteServerCode
        }

        if let error = location_simulation_new(remoteServer, &locationSimulation) {
            lastFailureDetail = consumeError(error, fallback: "location_simulation_new failed")
            cleanup()
            return simulationCreate
        }
        // location_simulation_new owns the remote-server lifecycle.
        remoteServer = nil

        if let error = location_simulation_set(locationSimulation, latitude, longitude) {
            lastFailureDetail = consumeError(error, fallback: "location_simulation_set failed")
            cleanup()
            return locationSet
        }
        return ok
    }

    /// CoreDeviceProxy route for iOS 18–26.3.
    ///
    /// The RPPairing createListener path is not reliable for an app connecting
    /// back to its own iPhone through LocalDevVPN: the ephemeral tunnel listener
    /// is bound to the Wi-Fi interface, not the VPN's reflected peer address.
    /// CoreDeviceProxy instead uses lockdownd's stable TCP service and a classic
    /// pairing record, then keeps the lockdown heartbeat alive for the tunnel.
    private static func openCoreDeviceProxyTunnel(deviceIP: String) -> Int32 {
        guard FileManager.default.fileExists(atPath: lockdownPairingPath) else {
            lastFailureDetail = LocusLocalization.string(
                "This iOS version needs a classic Lockdown pairing record for CoreDeviceProxy. The existing RPPairing file alone is not enough. Import the trusted computer pairing record into Locus, then try again."
            )
            return pairingRead
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        // idevice_tcp_provider_new selects the service port itself.
        address.sin_port = 0
        guard deviceIP.withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else {
            lastFailureDetail = "Invalid LocalDevVPN Device IP: \(deviceIP)"
            return invalidIP
        }

        var pairingHandle: OpaquePointer?
        if let error = lockdownPairingPath.withCString({ idevice_pairing_file_read($0, &pairingHandle) }) {
            lastFailureDetail = consumeError(error, fallback: "Could not read the classic Lockdown pairing record")
            return pairingRead
        }
        guard let pairingHandle else {
            lastFailureDetail = "The classic Lockdown pairing record returned an empty handle."
            return pairingRead
        }

        var pairingHandleOwned = true
        defer {
            if pairingHandleOwned {
                idevice_pairing_file_free(pairingHandle)
            }
        }

        var provider: OpaquePointer?
        let providerError = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                idevice_tcp_provider_new($0, pairingHandle, "LocusLocation", &provider)
            }
        }
        if providerError == nil {
            // idevice_tcp_provider_new consumes the pairing handle on success.
            pairingHandleOwned = false
        }
        if let error = consumeError(providerError, fallback: "idevice_tcp_provider_new failed") {
            lastFailureDetail = error
            return tunnelCreate
        }
        guard let provider else {
            lastFailureDetail = "idevice_tcp_provider_new returned a null provider."
            return tunnelCreate
        }
        defer { idevice_provider_free(provider) }

        var heartbeatClient: OpaquePointer?
        if let error = heartbeat_connect(provider, &heartbeatClient) {
            lastFailureDetail = consumeError(error, fallback: "Could not start the Lockdown heartbeat")
            return tunnelCreate
        }
        guard let heartbeatClient else {
            lastFailureDetail = "heartbeat_connect returned a null client."
            return tunnelCreate
        }

        let heartbeat = LockdownHeartbeat(client: heartbeatClient)
        lockdownHeartbeat = heartbeat
        guard heartbeat.waitUntilAnswered(timeout: 5) else {
            lastFailureDetail = "The iPhone did not answer the first Lockdown heartbeat within 5 seconds."
            heartbeat.stop()
            lockdownHeartbeat = nil
            return tunnelCreate
        }

        var newAdapter: OpaquePointer?
        var newHandshake: OpaquePointer?
        if let error = consumeError(tunnel_create_usb(provider, &newAdapter, &newHandshake),
                                    fallback: "CoreDeviceProxy tunnel_create_usb failed") {
            lastFailureDetail = error
            heartbeat.stop()
            lockdownHeartbeat = nil
            return tunnelCreate
        }
        guard let newAdapter, let newHandshake else {
            lastFailureDetail = "CoreDeviceProxy returned an empty adapter or RSD handshake."
            heartbeat.stop()
            lockdownHeartbeat = nil
            return tunnelCreate
        }

        adapter = newAdapter
        handshake = newHandshake
        NSLog("[Locus] CoreDeviceProxy tunnel opened through LocalDevVPN peer %@.", deviceIP)
        return ok
    }

    /// RPPairing route retained for iOS 26.4+.
    private static func openRemotePairingTunnel(pairingPath: String, deviceIP: String) -> Int32 {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(49152).bigEndian
        guard deviceIP.withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else {
            lastFailureDetail = "Invalid LocalDevVPN Device IP: \(deviceIP)"
            return invalidIP
        }

        var pairingHandle: OpaquePointer?
        if let error = pairingPath.withCString({ rp_pairing_file_read($0, &pairingHandle) }) {
            lastFailureDetail = consumeError(error, fallback: "Could not read the RPPairing file")
            return pairingRead
        }
        guard let pairingHandle else {
            lastFailureDetail = "rp_pairing_file_read returned a null handle."
            return pairingRead
        }
        defer { rp_pairing_file_free(pairingHandle) }

        let error = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                tunnel_create_rppairing(
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.stride),
                    "LocusLocation",
                    pairingHandle,
                    nil,
                    nil,
                    &adapter,
                    &handshake
                )
            }
        }
        if let detail = consumeError(error, fallback: "tunnel_create_rppairing failed") {
            lastFailureDetail = detail
            cleanup()
            return tunnelCreate
        }
        return ok
    }

    private static func clearLocked() -> Int32 {
        guard let locationSimulation else { return locationClear }
        let error = location_simulation_clear(locationSimulation)
        cleanup()
        if let detail = consumeError(error, fallback: "location_simulation_clear failed") {
            lastFailureDetail = detail
            return locationClear
        }
        return ok
    }
}

/// Keeps lockdownd's heartbeat answered for as long as CoreDeviceProxy is open.
/// iOS closes the tunnel shortly after this connection stops answering.
private final class LockdownHeartbeat {
    private struct Failure {
        let code: Int32
        let subCode: Int32
        let message: String
    }

    private let client: OpaquePointer
    private let condition = NSCondition()
    private var answered = 0
    private var ended = false
    private var stopped = false

    init(client: OpaquePointer) {
        self.client = client
        let thread = Thread { [self] in run() }
        thread.name = "locus.lockdown-heartbeat"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    func waitUntilAnswered(timeout: TimeInterval) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        condition.lock()
        defer { condition.unlock() }
        while answered == 0, !ended, !stopped {
            if !condition.wait(until: deadline) { break }
        }
        return answered > 0
    }

    func stop() {
        condition.lock()
        stopped = true
        condition.broadcast()
        condition.unlock()
    }

    private var isStopped: Bool {
        condition.lock()
        defer { condition.unlock() }
        return stopped
    }

    private func takeError(
        _ error: UnsafeMutablePointer<IdeviceFfiError>?,
        fallback: String
    ) -> Failure? {
        guard let error else { return nil }
        let code = error.pointee.code
        let subCode = error.pointee.sub_code
        let message = error.pointee.message.flatMap { String(validatingUTF8: $0) } ?? fallback
        idevice_error_free(error)
        return Failure(code: code, subCode: subCode, message: message)
    }

    private func run() {
        defer {
            heartbeat_client_free(client)
            condition.lock()
            ended = true
            condition.broadcast()
            condition.unlock()
        }

        var wait: UInt64 = 15
        while !isStopped {
            var interval: UInt64 = 0
            if let error = takeError(heartbeat_get_marco(client, wait, &interval),
                                    fallback: "heartbeat_get_marco failed") {
                if isStopped { return }
                // iOS uses code 100 for a late Marco or when the device is going to sleep.
                if error.code == 100 {
                    if error.subCode == 1 {
                        NSLog("[Locus] Lockdown heartbeat: iPhone is going to sleep.")
                    }
                    continue
                }
                NSLog("[Locus] Lockdown heartbeat ended: %@ (code=%d sub=%d).",
                      error.message, error.code, error.subCode)
                return
            }

            if isStopped { return }
            if let error = takeError(heartbeat_send_polo(client),
                                    fallback: "heartbeat_send_polo failed") {
                NSLog("[Locus] Lockdown heartbeat could not answer: %@ (code=%d sub=%d).",
                      error.message, error.code, error.subCode)
                return
            }

            wait = interval + 5
            condition.lock()
            answered += 1
            condition.broadcast()
            condition.unlock()
        }
    }
}
