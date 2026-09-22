import SwiftUI

struct MetadataEditorView: View {
    @EnvironmentObject private var model: GalleryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var profile: SyntheticMetadataProfile
    @State private var showsMap = false
    @State private var showsPresetName = false
    @State private var presetName = ""
    @State private var error: String?
    let mediaKind: GalleryMediaKind
    let actionTitle: String
    let action: (SyntheticMetadataProfile) -> Void

    init(profile: SyntheticMetadataProfile = MetadataForge.randomProfile(), mediaKind: GalleryMediaKind = .photo, actionTitle: String = "Share Copy",
         action: @escaping (SyntheticMetadataProfile) -> Void) {
        _profile = State(initialValue: profile)
        self.mediaKind = mediaKind
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        NavigationStack {
            Form {
                if !model.presets.isEmpty {
                    Section {
                        Menu {
                            ForEach(model.presets) { preset in
                                Button(preset.name) { profile = preset.profile }
                            }
                        } label: { Label("Use a saved preset", systemImage: "square.stack") }
                    }
                }
                Section {
                    Toggle("Include camera metadata", isOn: Binding(get: { profile.includesEquipment }, set: { profile.includeEquipment = $0 }))
                    Text("Turn off to include only the date and optional location.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if profile.includesEquipment {
                    Section {
                        NavigationLink {
                            DecoyEquipmentPicker(selection: $profile.equipmentID)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(profile.equipment.title)
                                Text("Choose camera & lens").font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 3)
                        }
                        if mediaKind == .photo {
                            LabeledContent("Focal length", value: "\(profile.equipment.equivalentFocalLength) mm equivalent")
                        }
                    } header: { Text("Equipment") } footer: {
                        Text("\(DecoyEquipment.modelNames.count) models · \(DecoyEquipment.catalog.count) camera and lens combinations")
                    }
                    if mediaKind == .photo {
                        Section("Exposure") {
                            Picker("Light", selection: Binding(get: { profile.scene }, set: { profile.scene = $0; varyExposure() })) {
                                ForEach(DecoyScene.allCases) { scene in Text(scene.title).tag(scene) }
                            }
                            Picker("Aperture", selection: exposureBinding(\.aperture)) {
                                ForEach(profile.equipment.apertures, id: \.self) { Text("ƒ/\($0.formatted())").tag($0) }
                            }.disabled(profile.equipment.apertures.count == 1)
                            Picker("Shutter", selection: exposureBinding(\.shutterDenominator)) {
                                ForEach(profile.equipment.shutterDenominators, id: \.self) { Text("1/\($0) s").tag($0) }
                            }
                            Picker("ISO", selection: exposureBinding(\.iso)) {
                                ForEach(profile.equipment.isoValues, id: \.self) { Text("\($0)").tag($0) }
                            }
                            Button("Vary Exposure", systemImage: "shuffle") { varyExposure() }
                        }
                    } else {
                        Section {
                            Text("Videos include camera, date and optional location. Photo exposure and lens tags are omitted.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Capture date") {
                    DatePicker("Date & time", selection: $profile.capturedAt,
                        in: SyntheticMetadataProfile.earliestDate...Date())
                        .environment(\.timeZone, profile.timeZone)
                    if profile.location == nil {
                        NavigationLink {
                            MetadataTimeZonePicker(selection: Binding(get: { profile.timeZone.identifier },
                                set: { profile.captureTimeZoneIdentifier = $0 }))
                        } label: { LabeledContent("Time zone", value: profile.timeZone.identifier.replacingOccurrences(of: "_", with: " ")) }
                    } else {
                        Text("Time zone: \(profile.timeZone.identifier)").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Location") {
                    Toggle("Include GPS", isOn: Binding(
                        get: { profile.location != nil },
                        set: { include in
                            profile.captureTimeZoneIdentifier = profile.timeZone.identifier
                            profile.location = include ? DecoyLocation.places[0] : nil
                        }
                    ))
                    if let location = profile.location {
                        Button { showsMap = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "map.fill").font(.title2).foregroundStyle(NoctGalleryTheme.accent)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(location.name).foregroundStyle(.primary)
                                    Text(coordinateLabel(location)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, 6)
                        }
                        .accessibilityIdentifier("metadata.chooseLocation")
                    }
                }
                Section {
                    Button("Randomize Profile", systemImage: "shuffle") { profile = MetadataForge.randomProfile(includeLocation: profile.location != nil, includeEquipment: profile.includesEquipment) }
                    Button("Save as Camera Preset…", systemImage: "square.and.arrow.down") {
                        presetName = profile.displayName
                        showsPresetName = true
                    }
                }
                Section {
                    Text("Replaces source metadata with these settings. Synthetic metadata may be recognizable; it cannot hide what the media shows.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle("Edit Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(actionTitle) {
                        do { action(try profile.validated()); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("metadata.apply")
                }
            }
            .onChange(of: profile.equipmentID) { _, _ in
                if !profile.equipment.accepts(profile.exposure) { varyExposure() }
            }
            .sheet(isPresented: $showsMap) {
                MetadataMapView(location: profile.location ?? DecoyLocation.places[0]) { profile.location = $0 }
            }
            .alert("Save Preset", isPresented: $showsPresetName) {
                TextField("Preset name", text: $presetName)
                Button("Cancel", role: .cancel) {}
                Button("Save") { model.savePreset(name: presetName, profile: profile) }
            } message: { Text("Use the same equipment, place and date offset for private camera captures.") }
        }
    }

    private func exposureBinding<T>(_ keyPath: WritableKeyPath<DecoyExposure, T>) -> Binding<T> {
        Binding(get: { profile.exposure[keyPath: keyPath] }, set: { value in
            var exposure = profile.exposure
            exposure[keyPath: keyPath] = value
            profile.exposureOverride = exposure
        })
    }
    private func varyExposure() {
        var generator = SystemRandomNumberGenerator()
        profile.exposureOverride = profile.equipment.randomExposure(for: profile.scene, using: &generator)
    }
    private func coordinateLabel(_ location: DecoyLocation) -> String {
        String(format: "%.5f, %.5f", location.latitude, location.longitude)
    }
}

struct CameraMetadataSettingsView: View {
    @EnvironmentObject private var model: GalleryViewModel
    @State private var editingPreset = false
    @State private var choosingRandomArea = false

    var body: some View {
        Form {
            Section {
                Picker("Apply before saving", selection: $model.cameraMetadataMode) {
                    ForEach(CameraMetadataMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                switch model.cameraMetadataMode {
                case .clean:
                    Text("Remove camera, time and location metadata from each private capture.")
                        .font(.footnote).foregroundStyle(.secondary)
                case .random:
                    Text("Randomize camera, exposure and date for each capture. Location is optional.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Toggle("Include camera metadata", isOn: $model.randomIncludesEquipment)
                    Toggle("Include random GPS", isOn: $model.randomIncludesLocation)
                    if model.randomIncludesLocation {
                        Button { choosingRandomArea = true } label: {
                            LabeledContent("Area", value: model.randomLocationCenter?.name ?? "Worldwide regions")
                        }
                        if model.randomLocationCenter != nil {
                            Button("Use Worldwide Regions") { model.randomLocationCenter = nil }
                        }
                        Picker("Radius", selection: $model.randomLocationRadius) {
                            ForEach([0.5, 1.0, 5.0, 10.0, 25.0], id: \.self) { Text("\($0.formatted()) km").tag($0) }
                        }
                        Text("Random places may fall on water or private property. Check the map before sharing.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                case .preset:
                    Picker("Preset", selection: $model.selectedPresetID) {
                        Text("Choose a preset").tag("")
                        ForEach(model.presets) { preset in Text(preset.name).tag(preset.id.uuidString) }
                    }
                    Text("Use the preset’s camera, place and date offset.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: { Text("Camera metadata") }
            Section("Saved presets") {
                ForEach(model.presets) { preset in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preset.name)
                        Text("\(preset.profile.displayName) · \(preset.profile.location?.name ?? "No GPS")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .swipeActions { Button("Delete", role: .destructive) { model.deletePreset(preset) } }
                }
                Button("Create Preset", systemImage: "plus") { editingPreset = true }
            }
        }
        .navigationTitle("Camera Metadata")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $choosingRandomArea) {
            MetadataMapView(location: model.randomLocationCenter ?? DecoyLocation.places[0]) { model.randomLocationCenter = $0 }
        }
        .sheet(isPresented: $editingPreset) {
            MetadataEditorView(actionTitle: "Save Preset") { profile in
                model.savePreset(name: profile.displayName, profile: profile)
            }
        }
    }
}

private struct DecoyEquipmentPicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var body: some View {
        List {
            ForEach(DecoyEquipment.brands, id: \.self) { brand in
                let cameras = DecoyEquipment.catalog.filter {
                    $0.make == brand && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query))
                }
                if !cameras.isEmpty {
                    Section(brand) {
                        ForEach(cameras) { camera in
                            Button {
                                selection = camera.id; dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(camera.title).foregroundStyle(.primary)
                                        Text("\(camera.equivalentFocalLength) mm equivalent · ƒ/\(camera.apertures[0].formatted())")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 4)
                                    if camera.id == selection { Image(systemName: "checkmark").foregroundStyle(NoctGalleryTheme.accent) }
                                }.padding(.vertical, 3)
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
        }.navigationTitle("Camera & Lens").navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Camera, model or lens")
    }
}

private struct MetadataTimeZonePicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    var body: some View {
        List {
            ForEach((["GMT"] + TimeZone.knownTimeZoneIdentifiers).filter {
                query.isEmpty || $0.replacingOccurrences(of: "_", with: " ").localizedCaseInsensitiveContains(query)
            }, id: \.self) { zone in
                Button { selection = zone; dismiss() } label: {
                    HStack {
                        Text(zone.replacingOccurrences(of: "_", with: " ")).foregroundStyle(.primary)
                        Spacer()
                        if zone == selection { Image(systemName: "checkmark").foregroundStyle(NoctGalleryTheme.accent) }
                    }
                }
            }
        }.navigationTitle("Time Zone").navigationBarTitleDisplayMode(.inline).searchable(text: $query, prompt: "City or region")
    }
}
