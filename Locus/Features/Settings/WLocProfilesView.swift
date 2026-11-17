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
    @State private var accuracyMeters = 25.0
    @State private var randomRadiusMeters = 0.0
    @State private var profileToEdit: WLocProfile?
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
                Stepper(value: $accuracyMeters, in: 1...10_000, step: 5) {
                    LabeledContent("WLOC accuracy (export only)") {
                        Text("\(Int(accuracyMeters)) m").monospacedDigit()
                    }
                }
                Stepper(value: $randomRadiusMeters, in: 0...10_000, step: 10) {
                    LabeledContent("Random radius") {
                        Text("\(Int(randomRadiusMeters)) m").monospacedDigit()
                    }
                }
                Button {
                    saveCurrentPin()
                } label: {
                    Label("Save current map pin", systemImage: "mappin.and.ellipse")
                }
                .disabled(session.pin == nil || profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } footer: {
                Text("Profiles are stored locally on this iPhone. Saving a pin records its current map coordinate reference; it does not change the device location by itself. The WLOC accuracy value is preserved for export compatibility only; the current Apple DVT engine cannot set horizontal accuracy. Random radius is applied once before each activation.")
            }

            Section {
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
            } header: {
                Text("Set from map link")
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
                                Text("WLOC accuracy (export only): \(Int(profile.accuracyMeters)) m")
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
                                Spacer()
                                if let wlocJSON = try? WLocProfile.exportWLOCJSON(profile) {
                                    ShareLink(item: wlocJSON, subject: Text("WLOC settings")) {
                                        Image(systemName: "square.and.arrow.up")
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Export WLOC JSON")
                                }
                                Menu {
                                    Button {
                                        profileToEdit = profile
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        delete(profile)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Profile actions for \(profile.name)")
                            }
                            .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: delete(at:))
                }
            }


            if !session.favorites.isEmpty {
                Section("Import from Favorites") {
                    ForEach(session.favorites) { place in
                        importPlaceRow(place)
                    }
                }
            }

            if !session.recents.isEmpty {
                Section("Import from Recents") {
                    ForEach(session.recents) { place in
                        importPlaceRow(place)
                    }
                }
            }

            Section("Device location") {
                LabeledContent("Status") {
                    Text(LocalizedStringKey(session.isSpoofing ? "Active" : "Not active"))
                }
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

            Section("Shortcuts") {
                Text("Use locusfix://share?url=<URL-encoded map link> to parse and apply a shared map location. Use locusfix://restore to return to the real location.")
                    .font(.footnote)
                    .textSelection(.enabled)
                Text("A Share Sheet shortcut can URL-encode its input, then open the generated Locus URL.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Compatibility") {
                LabeledContent("Storage") { Text("On this device") }
                LabeledContent("Format") { Text("Locus v1 / WLOC settings") }
                LabeledContent("Network access") { Text("Not required for profile storage") }
                Text("The current Apple DVT API accepts latitude and longitude only. It cannot set horizontal or vertical accuracy, altitude, speed, or course. WLOC accuracy is preserved for import/export compatibility only; random radius is applied once to the target coordinate before activation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Profiles are stored locally. They do not configure a VPN, install certificates, or modify network responses.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Location profiles")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $profileToEdit) { profile in
            WLocProfileEditorView(profile: profile) { updated in
                guard let index = profiles.firstIndex(where: { $0.id == updated.id }) else { return }
                profiles[index] = updated
                WLocProfile.save(profiles)
            }
        }
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
            actionError = LocusLocalization.string("The clipboard does not contain a map link or coordinate.")
            return
        }
        mapLinkText = value
    }

    @MainActor
    private func parseAndApplyMapLink() async {
        guard pairing.hasPairingFile else {
            actionError = LocusLocalization.string("Import an RPPairing file in Settings first.")
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

            let coordinate = profile.activationCoordinate(for: .current)
            session.teleport(to: coordinate, pairing: pairing, recentName: profile.name)
            guard session.isSpoofing else {
                actionError = session.lastError ?? LocusLocalization.string("Could not apply this location. Check the device connection.")
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
        onRestore()
    }

    private func restoreRealLocation() {
        session.stop(pairing: pairing)
        guard case .idle = session.status else {
            actionError = session.lastError ?? LocusLocalization.string("Could not restore the real location.")
            return
        }
        onRestore()
    }

    private func importPlaceRow(_ place: SavedPlace) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name)
                Text(LocalizedStringKey(place.coordinateReference ?? "Legacy coordinate"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                saveAsProfile(place)
            } label: {
                Label("Save as WLOC profile", systemImage: "plus.circle")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Save as WLOC profile")
            .disabled(isAlreadySavedAsProfile(place))
        }
    }

    private func isAlreadySavedAsProfile(_ place: SavedPlace) -> Bool {
        let candidate = WLocProfile.fromSavedPlace(place, mapMode: .current)
        let coordinate = candidate.mapCoordinate(for: .current)
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return profiles.contains { existing in
            let existingCoordinate = existing.mapCoordinate(for: .current)
            return target.distance(from: CLLocation(
                latitude: existingCoordinate.latitude,
                longitude: existingCoordinate.longitude
            )) < 2
        }
    }

    private func saveAsProfile(_ place: SavedPlace) {
        guard !isAlreadySavedAsProfile(place) else {
            importMessage = LocusLocalization.string("Already saved as a profile.")
            return
        }
        let profile = WLocProfile.fromSavedPlace(place, mapMode: .current)
        guard profile.isValid else { return }
        profiles.insert(profile, at: 0)
        WLocProfile.save(profiles)
        importMessage = LocusLocalization.string("Saved as a WLOC profile.")
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
            coordinateReference: reference,
            accuracyMeters: accuracyMeters,
            randomRadiusMeters: randomRadiusMeters
        )
        guard profile.isValid else { return }
        profiles.insert(profile, at: 0)
        WLocProfile.save(profiles)
        profileName = ""
        accuracyMeters = 25
        randomRadiusMeters = 0
        importMessage = LocusLocalization.string("Profile saved on this device.")
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
            let additions = imported.filter { candidate in
                !profiles.contains { existing in
                    existing.id == candidate.id
                        || (existing.name.caseInsensitiveCompare(candidate.name) == .orderedSame
                            && abs(existing.latitude - candidate.latitude) < 0.000001
                            && abs(existing.longitude - candidate.longitude) < 0.000001
                            && existing.accuracyMeters == candidate.accuracyMeters
                            && existing.randomRadiusMeters == candidate.randomRadiusMeters)
                }
            }
            profiles.append(contentsOf: additions)
            WLocProfile.save(profiles)
            importMessage = LocusLocalization.string("Imported \(additions.count) profile(s). WLOC accuracy is preserved for export compatibility only; DVT applies coordinates only.")
        } catch {
            importMessage = LocusLocalization.string("Import failed: \(error.localizedDescription)")
        }
    }
}


private struct WLocProfileEditorView: View {
    let original: WLocProfile
    let onSave: (WLocProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var accuracyMeters: Double
    @State private var randomRadiusMeters: Double

    init(profile: WLocProfile, onSave: @escaping (WLocProfile) -> Void) {
        original = profile
        self.onSave = onSave
        _name = State(initialValue: profile.name)
        _accuracyMeters = State(initialValue: profile.accuracyMeters)
        _randomRadiusMeters = State(initialValue: profile.randomRadiusMeters)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Profile name", text: $name)
                    LabeledContent("Coordinates", value: String(format: "%.6f, %.6f", original.latitude, original.longitude))
                    LabeledContent("Coordinate reference", value: original.coordinateReference)
                }

                Section("WLOC parameters") {
                    Stepper(value: $accuracyMeters, in: 1...10_000, step: 5) {
                        LabeledContent("WLOC accuracy (export only)") {
                            Text("\(Int(accuracyMeters)) m").monospacedDigit()
                        }
                    }
                    Stepper(value: $randomRadiusMeters, in: 0...10_000, step: 10) {
                        LabeledContent("Random radius") {
                            Text("\(Int(randomRadiusMeters)) m").monospacedDigit()
                        }
                    }
                }

                Section {
                    Text("The WLOC accuracy value is preserved for export compatibility only. Apple DVT applies coordinates but does not accept a horizontal-accuracy value. Random radius is applied once before activation.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let updated = WLocProfile(
                            id: original.id,
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            coordinate: original.coordinate,
                            coordinateReference: original.coordinateReference,
                            createdAt: original.createdAt,
                            accuracyMeters: accuracyMeters,
                            randomRadiusMeters: randomRadiusMeters
                        )
                        guard updated.isValid else { return }
                        onSave(updated)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
