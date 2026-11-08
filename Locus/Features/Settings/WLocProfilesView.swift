import CoreLocation
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct WLocProfilesView: View {
    let onRestore: () -> Void

    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore

    @State private var profiles = WLocProfile.load()
    @State private var actionError: String?
    @State private var profileName = ""
    @State private var mapLinkText = ""
    @State private var isParsingMapLink = false
    @State private var showImporter = false
    @State private var importMessage: String?

    private var exportJSON: String {
        (try? WLocProfile.exportJSON(profiles)) ?? ""
    }

    var body: some View {
        List {
            Section {
                TextField("Profile name", text: $profileName)
                    .textInputAutocapitalization(.words)
                Button {
                    saveCurrentPin()
                } label: {
                    Label("Save current map pin", systemImage: "mappin.and.ellipse")
                }
                .disabled(session.pin == nil || profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } footer: {
                Text("Profiles are stored locally on this iPhone. Saving a pin records its current map coordinate reference; it does not change the device location by itself.")
            }

            Section("Set from map link") {
                TextField("Paste Apple Maps / Amap / Google Maps link", text: $mapLinkText, axis: .vertical)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .lineLimit(2...4)
                HStack {
                    Button {
                        pasteMapLink()
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    Spacer()
                    Button {
                        Task { await parseAndApplyMapLink() }
                    } label: {
                        if isParsingMapLink {
                            ProgressView()
                        } else {
                            Label("Parse and apply", systemImage: "location.fill")
                        }
                    }
                    .disabled(mapLinkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isParsingMapLink)
                }
            } footer: {
                Text("Paste a shared map link or coordinates. Supported short links are expanded on this iPhone; the resolved coordinate is converted and applied through Locus.")
            }

            Section("Saved profiles") {
                if profiles.isEmpty {
                    ContentUnavailableView(
                        "No saved profiles",
                        systemImage: "mappin.slash",
                        description: Text("Choose a point on the map, enter a name, and save it here.")
                    )
                } else {
                    ForEach(profiles) { profile in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(profile.name).font(.headline)
                                Spacer()
                                Text(profile.coordinateReference)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                            }
                            Text(String(format: "%.6f, %.6f", profile.latitude, profile.longitude))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                Text("Accuracy metadata: \(Int(profile.accuracyMeters)) m")
                                if profile.randomRadiusMeters > 0 {
                                    Text("Radius: \(Int(profile.randomRadiusMeters)) m")
                                }
                            }
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            HStack {
                                Button {
                                    apply(profile)
                                } label: {
                                    Label("Apply", systemImage: "location.fill")
                                }
                                .buttonStyle(.borderless)

                                Button {
                                    showOnMap(profile)
                                } label: {
                                    Label("Map", systemImage: "map")
                                }
                                .buttonStyle(.borderless)
                                Spacer()
                                Button(role: .destructive) {
                                    delete(profile)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Delete \(profile.name)")
                            }
                            .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: delete(at:))
                }
            }


            Section("Device location") {
                LabeledContent("Status", value: session.isSpoofing ? "Active" : "Not active")
                if session.isSpoofing {
                    Button(role: .destructive) {
                        restoreRealLocation()
                    } label: {
                        Label("Restore real location", systemImage: "location.slash")
                    }
                } else {
                    Text("Apply a saved profile to start location simulation. You can restore the real location here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Backup and transfer") {
                Button {
                    showImporter = true
                } label: {
                    Label("Import Locus / WLOC JSON", systemImage: "square.and.arrow.down")
                }

                if !profiles.isEmpty {
                    ShareLink(
                        item: exportJSON,
                        subject: Text("Locus location profiles"),
                        preview: SharePreview("Locus profiles.json")
                    ) {
                        Label("Export profile JSON", systemImage: "square.and.arrow.up")
                    }
                    .disabled(exportJSON.isEmpty)
                }

                if let importMessage {
                    Text(importMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Compatibility") {
                LabeledContent("Storage", value: "On this device")
                LabeledContent("Format", value: "Locus v1 / WLOC settings")
                LabeledContent("Network access", value: "Not required for profile storage")
                Text("Accuracy is retained as WLOC metadata; the current DVT location engine applies coordinates but does not set horizontal accuracy. A random radius is applied once when a profile is activated to avoid continuous location jitter.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Profiles are stored locally. They do not configure a VPN, install certificates, or modify network responses.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Location profiles")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            importProfiles(result)
        }
        .alert("Locus", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
    }

    private func pasteMapLink() {
        guard let value = UIPasteboard.general.string,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            actionError = "The clipboard does not contain a map link or coordinate."
            return
        }
        mapLinkText = value
    }

    @MainActor
    private func parseAndApplyMapLink() async {
        guard pairing.hasPairingFile else {
            actionError = "Import an RPPairing file in Settings first."
            return
        }
        isParsingMapLink = true
        defer { isParsingMapLink = false }

        do {
            let profile = try await WLocMapLinkParser.parse(mapLinkText)
            if !profiles.contains(where: {
                abs($0.latitude - profile.latitude) < 0.000001
                    && abs($0.longitude - profile.longitude) < 0.000001
            }) {
                profiles.insert(profile, at: 0)
                WLocProfile.save(profiles)
            }

            let base = profile.mapCoordinate(for: MapDatumMode.current)
            let coordinate = randomizedCoordinate(base, radiusMeters: profile.randomRadiusMeters)
            session.teleport(to: coordinate, pairing: pairing)
            guard session.isSpoofing else {
                actionError = session.lastError ?? "Could not apply this location. Check the device connection."
                return
            }
            session.requestMapFocus(coordinate)
            onRestore()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func showOnMap(_ profile: WLocProfile) {
        let coordinate = profile.mapCoordinate(for: MapDatumMode.current)
        session.pin = coordinate
        session.requestMapFocus(coordinate)
        onRestore()
    }

    private func apply(_ profile: WLocProfile) {
        guard pairing.hasPairingFile else {
            actionError = "Import an RPPairing file in Settings first."
            return
        }

        let base = profile.mapCoordinate(for: MapDatumMode.current)
        let coordinate = randomizedCoordinate(base, radiusMeters: profile.randomRadiusMeters)
        session.teleport(to: coordinate, pairing: pairing)
        guard session.isSpoofing else {
            actionError = session.lastError ?? "Could not apply this location. Check the device connection."
            return
        }
        session.requestMapFocus(coordinate)
        onRestore()
    }

    private func restoreRealLocation() {
        session.stop(pairing: pairing)
        guard case .idle = session.status else {
            actionError = session.lastError ?? "Could not restore the real location."
            return
        }
        onRestore()
    }

    private func randomizedCoordinate(
        _ coordinate: CLLocationCoordinate2D,
        radiusMeters: Double
    ) -> CLLocationCoordinate2D {
        guard radiusMeters > 0 else { return coordinate }
        let distance = sqrt(Double.random(in: 0...1)) * radiusMeters
        let angle = Double.random(in: 0..<(2 * Double.pi))
        let northMeters = cos(angle) * distance
        let eastMeters = sin(angle) * distance
        let latitude = coordinate.latitude + northMeters / 111_320
        let longitudeScale = max(0.01, abs(cos(coordinate.latitude * .pi / 180)))
        let longitude = coordinate.longitude + eastMeters / (111_320 * longitudeScale)
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func saveCurrentPin() {
        guard let coordinate = session.pin,
              CLLocationCoordinate2DIsValid(coordinate) else { return }

        let reference = MapDatumMode.current == .automaticChina
            && ChinaCoordinateTransform.isWithinMainlandCoverage(coordinate)
            ? "GCJ-02"
            : "WGS-84"
        let profile = WLocProfile(
            name: profileName.trimmingCharacters(in: .whitespacesAndNewlines),
            coordinate: coordinate,
            coordinateReference: reference
        )
        guard profile.isValid else { return }
        profiles.insert(profile, at: 0)
        WLocProfile.save(profiles)
        profileName = ""
        importMessage = "Profile saved on this device."
    }

    private func delete(_ profile: WLocProfile) {
        profiles.removeAll { $0.id == profile.id }
        WLocProfile.save(profiles)
    }

    private func delete(at offsets: IndexSet) {
        profiles.remove(atOffsets: offsets)
        WLocProfile.save(profiles)
    }

    private func importProfiles(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let imported = try WLocProfile.importJSON(Data(contentsOf: url))
            let existingIDs = Set(profiles.map(\.id))
            let additions = imported.filter { !existingIDs.contains($0.id) }
            profiles.append(contentsOf: additions)
            WLocProfile.save(profiles)
            importMessage = "Imported \(additions.count) profile(s). WLOC accuracy is retained as metadata; Locus applies the saved coordinate."
        } catch {
            importMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}
