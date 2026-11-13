import Darwin
import Foundation
import UIKit

enum LocalDevVPN {
    static let appStoreURL = URL(string: "https://apps.apple.com/us/app/localdevvpn/id6755608044")!
    static let detectURL = URL(string: "localdevvpn://")!

    /// Starts the tunnel, then returns to Locus Fix Test via `locusfix://`.
    static let enableURL = URL(string: "localdevvpn://enable?scheme=locusfix")!

    static var isInstalled: Bool {
        UIApplication.shared.canOpenURL(detectURL)
    }

    /// LocalDevVPN's target IP is the remote endpoint; the local utun may use
    /// the adjacent address (for example, target 10.7.0.1 with tunnel IP 10.7.1.1).
    static var isConnected: Bool {
        let interfaces = ipv4InterfaceAddresses()
        let addresses = interfaces.map(\.address)
        let target = TunnelConfig.targetIP
        if addresses.contains(target) { return true }

        let parts = target.split(separator: ".")
        guard parts.count == 4 else { return false }

        // Preserve support for tunnels that expose the target's /24 locally.
        let targetPrefix = parts.dropLast().joined(separator: ".") + "."
        if addresses.contains(where: { $0.hasPrefix(targetPrefix) }) { return true }

        // LocalDevVPN reports its client-side address on a utun interface.
        // Match the target's private network prefix rather than expecting the
        // remote endpoint itself to appear as a local interface address.
        let tunnelPrefix = parts.prefix(2).joined(separator: ".") + "."
        return interfaces.contains {
            $0.name.hasPrefix("utun") && $0.address.hasPrefix(tunnelPrefix)
        }
    }

    static func openInstalled() {
        UIApplication.shared.open(enableURL)
    }

    static func openAppStore() {
        UIApplication.shared.open(appStoreURL)
    }

    /// Open LocalDevVPN to connect if installed; otherwise App Store.
    static func openOrInstall() {
        if isInstalled {
            openInstalled()
        } else {
            openAppStore()
        }
    }

    private static func ipv4InterfaceAddresses() -> [(name: String, address: String)] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var results: [(name: String, address: String)] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let interface = current.pointee
            if interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let nameLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                if getnameinfo(
                    interface.ifa_addr,
                    nameLen,
                    &host,
                    socklen_t(host.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    results.append((
                        name: String(cString: interface.ifa_name),
                        address: String(cString: host)
                    ))
                }
            }
            ptr = interface.ifa_next
        }
        return results
    }
}
