import CoreLocation
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    @State private var showImporter = false
    @State private var showPairOnDevice = false
    @State private var showNameEasterEgg = false
    @State private var tunnelIP = TunnelConfig.targetIP
    @AppStorage(MapDatumMode.defaultsKey) private var mapDatumMode = MapDatumMode.automaticChina.rawValue
    @AppStorage(LocusLocalization.languageKey) private var appLanguage = "system"
    @State private var localDevVPNInstalled = LocalDevVPN.isInstalled
    @State private var showLocationDiagnostics = false
    @Environment(\.scenePhase) private var scenePhase

    private var supportsOnDevicePairing: Bool {
        if #available(iOS 27.0, *) { return true }
        return false
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("App language", selection: $appLanguage) {
                        Text("System default").tag("system")
                        Text("English").tag("en")
                        Text("Simplified Chinese").tag("zh-Hans")
                    }
                } header: {
                    Text("Language")
                } footer: {
                    Text("You can switch between English and Simplified Chinese at any time.")
                }

                Section {
                    Label {
                        Text(LocalizedStringKey(pairing.hasPairingFile ? "RPPairing file installed" : "No pairing file"))
                    } icon: {
                        Image(systemName: pairing.hasPairingFile ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(pairing.hasPairingFile ? LocusTheme.statusGood : LocusTheme.statusWarn)
                    }

                    if supportsOnDevicePairing {
                        Button {
                            showPairOnDevice = true
                        } label: {
                            Label("Pair on this iPhone", systemImage: "iphone.gen3.radiowaves.left.and.right")
                        }
                    }

                    Button("Import RPPairing file…") { showImporter = true }
                    Button("Paste RPPairing from clipboard") {
                        do {
                            try pairing.importPairingFromClipboard()
                        } catch {
                            session.lastError = error.localizedDescription
                        }
                    }
                    if pairing.hasPairingFile {
                        Button("Remove pairing file", role: .destructive) {
                            try? pairing.removePairing()
                        }
                    }
                } header: {
                    Text("Developer pairing")
                } footer: {
                    Text(LocalizedStringKey(supportsOnDevicePairing
                         ? "On iOS 27, use Pair on this iPhone — no computer. Locus advertises a pairable host; confirm the 6-digit code under Settings › Privacy & Security › Developer Mode › Pair with Host. On older iOS, import an RPPairing file from idevice_pair (not a SideStore lockdown .mobiledevicepairing). LiveContainer: enable Fix File Picker on Locus, or use Paste / Share → LiveContainer → Locus."
                         : "Import an RPPairing file from idevice_pair (not a SideStore lockdown .mobiledevicepairing). If the file picker fails (common in LiveContainer), enable Fix File Picker on the app, share the file into LiveContainer → Locus, or copy the plist and use Paste."))
                }

                Section {
                    TextField("Device tunnel IP", text: $tunnelIP)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            TunnelConfig.setTargetIP(tunnelIP)
                        }
                    LabeledContent("Status") {
                        Text(LocalizedStringKey(LocalDevVPN.isConnected ? "Connected" : "Not connected"))
                            .foregroundStyle(LocalDevVPN.isConnected ? LocusTheme.statusGood : LocusTheme.statusWarn)
                    }
                    Button("Save tunnel IP") {
                        TunnelConfig.setTargetIP(tunnelIP)
                    }
                    Button {
                        if localDevVPNInstalled {
                            LocalDevVPN.openInstalled()
                        } else {
                            LocalDevVPN.openAppStore()
                        }
                    } label: {
                        Label {
                            Text(LocalizedStringKey(localDevVPNInstalled ? "Open LocalDevVPN" : "Get LocalDevVPN (App Store)"))
                        } icon: {
                            Image(systemName: localDevVPNInstalled ? "lock.shield.fill" : "arrow.down.app.fill")
                        }
                    }
                } header: {
                    Text("Tunnel")
                } footer: {
                    Text("Connect LocalDevVPN before teleporting. Default tunnel IP is 10.7.0.1. Start a spoof on Wi‑Fi first; it can keep working on cellular afterward.")
                }

                Section {
                    Picker("China map coordinate correction", selection: $mapDatumMode) {
                        ForEach(MapDatumMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .disabled(session.isSpoofing || session.isBusy || session.simulated != nil)
                } footer: {
                    Text("Automatic mode aligns mainland-China map coordinates (GCJ-02) with the iPhone's WGS-84 location. GPX import and export use WGS-84 and are converted for the map automatically. Stop the active session before changing this setting. Leave Off outside mainland China and near border areas.")
                }

                Section {
                    NavigationLink {
                        WLocProfilesView(onRestore: { dismiss() })
                            .environmentObject(session)
                    } label: {
                        Label("Location profiles", systemImage: "mappin.and.ellipse")
                    }
                } header: {
                    Text("WLOC-compatible tools")
                } footer: {
                    Text("Save, restore, import, and export named map coordinates locally. This module does not require a VPN or network extension.")
                }

                Section("Location diagnostics") {
                    Button {
                        showLocationDiagnostics = true
                    } label: {
                        Label("View location diagnostics", systemImage: "waveform.path.ecg")
                    }
                }

                Section("Privacy") {
                    Text("Fully on-device. Favorites and recents stay in UserDefaults. No analytics, no accounts, nothing uploaded.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Engine") {
                        Text("idevice DVT location simulation")
                    }
                    Text("Locus is free and open source (MIT). Location injection uses the MIT-licensed idevice FFI.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        showNameEasterEgg = true
                    } label: {
                        Text("locus, n. — a place. From the Latin for where you are.")
                            .font(.footnote.italic())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        TunnelConfig.setTargetIP(tunnelIP)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showImporter) {
            PairingDocumentPicker(
                onPick: { url in
                    showImporter = false
                    do {
                        try pairing.importPairing(from: url)
                    } catch {
                        session.lastError = error.localizedDescription
                    }
                },
                onCancel: { showImporter = false }
            )
            .ignoresSafeArea()
        }
            .sheet(isPresented: $showPairOnDevice) {
                PairOnDeviceView()
                    .environmentObject(pairing)
            }
            .sheet(isPresented: $showLocationDiagnostics) {
                LocationDiagnosticsView(session: session)
                    .presentationDetents([.medium, .large])
            }
            .fullScreenCover(isPresented: $showNameEasterEgg) {
                LocusEasterEggView()
            }
            .onAppear {
                localDevVPNInstalled = LocalDevVPN.isInstalled
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    localDevVPNInstalled = LocalDevVPN.isInstalled
                }
            }
        }
    }
}

struct PlacesView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss

    @State private var placeToRename: SavedPlace?
    @State private var renameText = ""
    @State private var actionError: String?
    @State private var profiles: [WLocProfile] = WLocProfile.load()

    private var alertPresented: Binding<Bool> {
        Binding(
            get: { placeToRename != nil || actionError != nil },
            set: {
                if !$0 {
                    placeToRename = nil
                    actionError = nil
                }
            }
        )
    }

    private var alertTitle: String {
        actionError == nil
            ? LocusLocalization.string("Rename Favorite")
            : LocusLocalization.string("Locus")
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Favorites") {
                    if session.favorites.isEmpty {
                        Text("Star a pin from the map to save it.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.favorites) { place in
                        placeButton(place)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    session.removeFavorite(place)
                                } label: {
                                    Label("Delete", systemImage: "trash.fill")
                                }
                                Button {
                                    placeToRename = place
                                    renameText = place.name
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.gray)
                            }
                    }
                }

                Section("Recents") {
                    if session.recents.isEmpty {
                        Text("Teleports show up here.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(session.recents) { place in
                        placeButton(place)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    session.removeRecent(place)
                                } label: {
                                    Label("Delete", systemImage: "trash.fill")
                                }
                            }
                    }
                }

                Section("WLOC Profiles") {
                    if profiles.isEmpty {
                        Text("WLOC profiles appear here after you save a place.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(profiles) { profile in
                        HStack(spacing: 12) {
                            Button {
                                activate(profile)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(profile.name)
                                        .foregroundStyle(.primary)
                                    Text("\(profile.coordinateReference) · \(String(format: "%.5f, %.5f", profile.latitude, profile.longitude))")
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Button {
                                session.addFavorite(
                                    name: profile.name,
                                    coordinate: profile.mapCoordinate(for: .current)
                                )
                            } label: {
                                Image(systemName: "star")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Add to Favorites")
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                profiles.removeAll { $0.id == profile.id }
                                WLocProfile.save(profiles)
                            } label: {
                                Label("Delete", systemImage: "trash.fill")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Places")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                profiles = WLocProfile.load()
            }
            .alert(alertTitle, isPresented: alertPresented) {
                if placeToRename != nil {
                    TextField("Name", text: $renameText)
                    Button("Cancel", role: .cancel) {
                        placeToRename = nil
                    }
                    Button("Save") {
                        if let place = placeToRename {
                            session.renameFavorite(place, to: renameText)
                        }
                        placeToRename = nil
                    }
                } else {
                    Button("OK", role: .cancel) {
                        actionError = nil
                    }
                }
            } message: {
                if let actionError {
                    Text(actionError)
                } else {
                    Text("Choose a name you’ll recognize later.")
                }
            }
        }
    }

    private func placeButton(_ place: SavedPlace) -> some View {
        Button {
            guard pairing.hasPairingFile else {
                actionError = LocusLocalization.string("Import an RPPairing file in Settings first.")
                return
            }
            let coordinate = place.mapCoordinate(for: .current)
            session.teleport(to: coordinate, pairing: pairing, recentName: place.name)
            guard session.isSpoofing else {
                actionError = session.lastError ?? LocusLocalization.string("Could not apply this location. Check the device connection.")
                return
            }
            session.requestMapFocus(coordinate)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).foregroundStyle(.primary)
                Text(String(format: "%.5f, %.5f", place.latitude, place.longitude))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func activate(_ profile: WLocProfile) {
        guard pairing.hasPairingFile else {
            actionError = LocusLocalization.string("Import an RPPairing file in Settings first.")
            return
        }
        let coordinate = profile.activationCoordinate(for: .current)
        session.teleport(to: coordinate, pairing: pairing, recentName: profile.name)
        guard session.isSpoofing else {
            actionError = session.lastError ?? LocusLocalization.string("Could not apply this location. Check the device connection.")
            return
        }
        session.requestMapFocus(coordinate)
        dismiss()
    }
}

private struct LocationDiagnosticsView: View {
    @ObservedObject var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    private var mapTarget: CLLocationCoordinate2D? {
        session.simulated ?? session.pin
    }

    private var deviceTarget: CLLocationCoordinate2D? {
        mapTarget.map { MapDatumMode.current.deviceCoordinate(fromMapCoordinate: $0) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Engine") {
                    LabeledContent("VPN") {
                        Text(LocalizedStringKey(LocalDevVPN.isConnected ? "Connected" : "Not connected"))
                    }
                    LabeledContent("DVT simulation") {
                        Text(LocalizedStringKey(LocationEngine.isSessionActive ? "Active" : "Inactive"))
                    }
                    LabeledContent("Session") {
                        Text(session.status.label)
                    }
                    LabeledContent("Coordinate mode", value: MapDatumMode.current.title)
                }

                Section("Engine capabilities") {
                    LabeledContent("Location API", value: "Apple DVT")
                    LabeledContent("Settable fields", value: "Latitude and longitude only")
                    LabeledContent("Horizontal accuracy", value: "Not configurable through this API")
                    LabeledContent("Altitude and motion", value: "Not configurable through this API")
                    Text("The fix-quality values below are reported by Locus's own Core Location manager. They are not accuracy values injected by DVT and do not prove what another app receives.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Coordinates") {
                    coordinateRow("Map target", coordinate: mapTarget)
                    coordinateRow("WGS-84 target", coordinate: deviceTarget)
                    if let fix = session.latestLocationSnapshot {
                        coordinateRow(
                            "Latest Core Location fix",
                            coordinate: CLLocationCoordinate2D(latitude: fix.latitude, longitude: fix.longitude)
                        )
                    } else {
                        Text("Waiting for a Core Location update…")
                            .foregroundStyle(.secondary)
                    }
                }

                if let fix = session.latestLocationSnapshot {
                    Section("Fix quality") {
                        LabeledContent("Horizontal accuracy", value: accuracyText(fix.horizontalAccuracy))
                        LabeledContent("Vertical accuracy", value: accuracyText(fix.verticalAccuracy))
                        LabeledContent("Altitude", value: metersText(fix.altitude))
                        LabeledContent("Speed", value: speedText(fix.speed))
                        LabeledContent("Course", value: degreesText(fix.course))
                        LabeledContent("Fix age", value: ageText(fix.timestamp))
                        LabeledContent("Authorization", value: fix.authorization)
                        LabeledContent("Precision permission", value: fix.accuracyAuthorization)
                    }

                    Section("Location source") {
                        LabeledContent("Software simulated", value: boolText(fix.isSimulatedBySoftware))
                        LabeledContent("External accessory", value: boolText(fix.isProducedByAccessory))
                    }
                }

                Section {
                    Text("These values are reported to Locus by its own Core Location manager. This screen cannot inspect what another app receives or how another service validates a location.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Location diagnostics")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func coordinateRow(_ title: String, coordinate: CLLocationCoordinate2D?) -> some View {
        LabeledContent(title) {
            if let coordinate {
                Text(String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude))
                    .font(.caption.monospaced())
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            } else {
                Text("—").foregroundStyle(.secondary)
            }
        }
    }

    private func accuracyText(_ value: CLLocationAccuracy) -> String {
        value >= 0 ? String(format: "%.1f m", value) : LocusLocalization.string("Unavailable")
    }

    private func metersText(_ value: CLLocationDistance) -> String {
        String(format: "%.1f m", value)
    }

    private func speedText(_ value: CLLocationSpeed) -> String {
        value >= 0 ? String(format: "%.2f m/s", value) : LocusLocalization.string("Unavailable")
    }

    private func degreesText(_ value: CLLocationDirection) -> String {
        value >= 0 ? String(format: "%.1f°", value) : "Unavailable"
    }

    private func ageText(_ timestamp: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(timestamp))
        return LocusLocalization.string("\(String(format: "%.1f", seconds)) s ago")
    }

    private func boolText(_ value: Bool?) -> String {
        guard let value else { return LocusLocalization.string("Unavailable") }
        return LocusLocalization.string(value ? "Yes" : "No")
    }
}
