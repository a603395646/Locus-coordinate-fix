import CoreLocation
import SwiftUI

enum LocusLocalization {
    static let languageKey = "locus.appLanguage"

    static var locale: Locale {
        switch UserDefaults.standard.string(forKey: languageKey) {
        case "zh-Hans": return Locale(identifier: "zh-Hans")
        case "en": return Locale(identifier: "en")
        default: return Locale(identifier: Bundle.main.preferredLocalizations.first ?? Locale.current.identifier)
        }
    }

    static func string(_ key: String.LocalizationValue) -> String {
        String(localized: key, locale: locale)
    }
}

@main
struct LocusApp: App {
    @StateObject private var session = SpoofSession()
    @StateObject private var pairing = PairingStore()
    @AppStorage(SetupGate.defaultsKey) private var setupComplete = false
    @AppStorage(LocusLocalization.languageKey) private var appLanguage = "system"

    private var appLocale: Locale {
        switch appLanguage {
        case "zh-Hans": return Locale(identifier: "zh-Hans")
        case "en": return Locale(identifier: "en")
        default: return Locale(identifier: Bundle.main.preferredLocalizations.first ?? Locale.current.identifier)
        }
    }

    /// Map when setup finished, or when already paired outside this walkthrough.
    private var showMap: Bool {
        setupComplete || (pairing.hasPairingFile && !SetupGate.isInProgress)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if showMap {
                    RootView()
                } else {
                    SetupFlowView(initialStep: SetupGate.initialStep(hasPairingFile: pairing.hasPairingFile)) {
                        SetupGate.markComplete()
                        setupComplete = true
                    }
                }
            }
            .environmentObject(session)
            .environmentObject(pairing)
            .environment(\.locale, appLocale)
            .preferredColorScheme(.dark)
            .onOpenURL { url in
                handleIncoming(url)
            }
            .onAppear {
                if !setupComplete, pairing.hasPairingFile, !SetupGate.isInProgress {
                    SetupGate.markComplete()
                    setupComplete = true
                }
            }
        }
    }

    private func handleIncoming(_ url: URL) {
        if url.scheme?.lowercased() == "locusfix" {
            handleLocusURL(url)
            return
        }

        let ext = url.pathExtension.lowercased()
        if ["plist", "mobiledevicepairing", "mobiledevicepair"].contains(ext) {
            try? pairing.importPairing(from: url)
        } else if ext == "gpx" {
            NotificationCenter.default.post(name: .locusImportGPX, object: url)
        }
    }

    /// URL actions let Apple Shortcuts hand a shared map link directly to Locus.
    /// Examples: locusfix://share?url=<encoded-link> and locusfix://restore
    private func handleLocusURL(_ url: URL) {
        guard let action = url.host?.lowercased() else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ key: String) -> String? {
            items.first(where: { $0.name.caseInsensitiveCompare(key) == .orderedSame })?.value
        }

        switch action {
        case "share":
            guard let sharedText = value("url") ?? value("text"),
                  !sharedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                session.lastError = LocusLocalization.string("The shared map link is empty.")
                return
            }
            Task { @MainActor in
                do {
                    let profile = try await WLocMapLinkParser.parse(sharedText)
                    let coordinate = profile.mapCoordinate(for: MapDatumMode.current)
                    session.teleport(to: coordinate, pairing: pairing)
                    if session.isSpoofing {
                        session.requestMapFocus(coordinate)
                    }
                } catch {
                    session.lastError = error.localizedDescription
                }
            }

        case "set":
            guard let latitude = value("lat").flatMap(Double.init),
                  let longitude = value("lon").flatMap(Double.init) else {
                session.lastError = LocusLocalization.string("The Locus URL needs valid lat and lon values.")
                return
            }
            let input = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            guard CLLocationCoordinate2DIsValid(input) else {
                session.lastError = LocusLocalization.string("The Locus URL contains an invalid coordinate.")
                return
            }
            let coordinate: CLLocationCoordinate2D
            if value("datum")?.lowercased() == "gcj02" {
                coordinate = MapDatumMode.current == .automaticChina
                    ? input
                    : MapDatumMode.automaticChina.deviceCoordinate(fromMapCoordinate: input)
            } else {
                coordinate = MapDatumMode.current.mapCoordinate(fromWGS84: input)
            }
            session.teleport(to: coordinate, pairing: pairing)
            if session.isSpoofing {
                session.requestMapFocus(coordinate)
            }

        case "restore":
            if session.isSpoofing {
                session.stop(pairing: pairing)
            }

        default:
            return
        }
    }
}

extension Notification.Name {
    static let locusImportGPX = Notification.Name("locusImportGPX")
}
