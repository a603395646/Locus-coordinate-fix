import CoreLocation
import SwiftUI
import UniformTypeIdentifiers

struct WLocProfilesView: View {
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss

    @State private var profiles = WLocProfile.load()
    @State private var profileName = ""
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
                            HStack {
                                Button {
                                    session.pin = profile.mapCoordinate(for: MapDatumMode.current)
                                    dismiss()
                                } label: {
                                    Label("Show on map", systemImage: "map")
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

            Section("Backup and transfer") {
                Button {
                    showImporter = true
                } label: {
                    Label("Import profile JSON", systemImage: "square.and.arrow.down")
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
                LabeledContent("Format", value: "Locus JSON v1")
                LabeledContent("Network access", value: "Not required")
                Text("This profile format is for saving and transferring coordinates within Locus. It does not configure a VPN, install certificates, or modify network responses.")
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
            importMessage = "Imported \(additions.count) profile(s)."
        } catch {
            importMessage = "Import failed: \(error.localizedDescription)"
        }
    }
}
