import SwiftUI

struct GallerySettingsView: View {
    @EnvironmentObject private var model: GalleryViewModel
    @EnvironmentObject private var lock: GalleryLockController
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @State private var showsResetConfirmation = false
    @State private var resetConfirmation = ""
    @State private var confirmsDisableRecovery = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Security") {
                    Button { lock.requestProtectionSettings() } label: {
                        LabeledContent { Text(lock.mode.title).foregroundStyle(.secondary) } label: {
                            Label("App Protection", systemImage: "lock.shield")
                        }
                    }
                    if lock.mode != .off {
                        Button("Lock Now", systemImage: "lock") { Task { await model.lockPrivate() } }
                    }
                }
                Section("Private camera") {
                    NavigationLink { CameraMetadataSettingsView() } label: {
                        Label("Camera Metadata", systemImage: "camera.filters")
                    }
                    LabeledContent("Capture mode", value: model.cameraMetadataMode.title)
                    Text("Captures stay encrypted in Gallery, outside Photos and backups.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Photo shares") {
                    Picker("Output format", selection: $model.shareOutputFormat) {
                        ForEach(GalleryOutputFormat.allCases) { format in
                            Text(format.title).tag(format.rawValue)
                        }
                    }
                    DisclosureGroup("Advanced Share Defaults") {
                        Picker("Maximum edge", selection: $model.shareMaximumDimension) {
                            Text("2,048 px").tag(2_048)
                            Text("4,096 px").tag(4_096)
                            Text("8,192 px").tag(8_192)
                        }
                        if selectedFormat != .png {
                            VStack(alignment: .leading, spacing: 8) {
                                LabeledContent("Lossy quality", value: model.shareLossyQuality.formatted(.percent.precision(.fractionLength(0))))
                                Slider(value: $model.shareLossyQuality, in: 0.65 ... 1.0, step: 0.01)
                            }
                        }
                        Text("JPEG is used if HEIC encoding is unavailable.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if !model.sharingPresets.isEmpty {
                    Section("Sharing presets") {
                        ForEach(model.sharingPresets) { preset in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(preset.name)
                                    Text("\(preset.format.title) · \(preset.maximumDimension) px · video \(preset.videoMaximumEdge) px")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Delete Preset", systemImage: "trash", role: .destructive) { model.deleteSharingPreset(preset.id) }.labelStyle(.iconOnly)
                            }
                        }
                    }
                }

                Section("Privacy & storage") {
                    Toggle("Recently Deleted", isOn: Binding(get: { model.organization.recentlyDeletedEnabled == true }, set: { enabled in
                        if !enabled, !model.recentlyDeletedItems.isEmpty { confirmsDisableRecovery = true }
                        else { Task { await model.setRecentlyDeleted(enabled: enabled) } }
                    })).disabled(!model.privateUnlocked || model.isOrganizing)
                    Text("Off by default. When enabled, ordinary deletions can be restored for seven days. Expired items are purged when Gallery runs while unlocked. Duress and reset erase them immediately.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if model.organization.recentlyDeletedEnabled == true { NavigationLink("Recently Deleted (\(model.recentlyDeletedItems.count))", destination: GalleryRecentlyDeletedView()) }
                    NavigationLink("Storage", destination: GalleryStorageView())
                    if model.showsSmartSearch {
                        NavigationLink("Smart Search", destination: GallerySmartSearchView())
                            .disabled(!model.smartFeaturesAvailable)
                            .foregroundStyle(model.smartFeaturesAvailable ? Color.primary : Color.secondary)
                            .accessibilityIdentifier("settings.smart-search")
                        if !model.smartFeaturesAvailable {
                            Text(model.queryInterpreterAvailability.message).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    NavigationLink("Private Text Search", destination: GalleryTextSearchView())
                    NavigationLink("Find Duplicates", destination: GalleryDuplicatesView())
                    NavigationLink("Incoming Shares", destination: GalleryInboxView())
                    DisclosureGroup("How sharing works") {
                        Text("Sharing creates clean copies; originals stay unchanged. Choose compact video copies or higher-quality H.264/AAC exports up to 4K and 60 fps, within source and device capabilities. Exports use standard dynamic range.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if model.hasTemporaryShareFiles {
                        Button("Clear Temporary Share Files", systemImage: "trash") {
                            Task { await model.purgeTemporaryExports() }
                        }
                    }
                    Text("Temporary copies are protected and removed when you close export review or lock Gallery.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Photo access") {
                    LabeledContent("Authorization", value: authorizationLabel)
                    Button("Open iOS Settings", systemImage: "gear") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    }
                }

                Section("Reset app") {
                    Button("Purge and Reset App…", role: .destructive) {
                        resetConfirmation = ""
                        showsResetConfirmation = true
                    }
                    .disabled(model.isResetting)
                    .accessibilityIdentifier("app.purgeAndReset")
                    Text("Erase all Gallery data and settings. Photos and shared copies are unaffected.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section { AppSupportCard().listRowInsets(EdgeInsets()) }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                    Text("No ads, analytics or tracking. Photos may download iCloud media. Maps uses Apple services without requesting your location.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(NoctGalleryTheme.background(for: colorScheme))
            .navigationTitle("Settings")
            .confirmationDialog("Turn off Recently Deleted?", isPresented: $confirmsDisableRecovery, titleVisibility: .visible) {
                Button("Delete Retained Items and Turn Off", role: .destructive) { Task { await model.setRecentlyDeleted(enabled: false, emptyFirst: true) } }
            } message: { Text("Items currently in Recently Deleted will be permanently erased. You can restore them first instead.") }
            .alert("Purge and reset Noct Gallery?", isPresented: $showsResetConfirmation) {
                TextField("Type RESET to confirm", text: $resetConfirmation)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) {}
                Button("Purge and Reset", role: .destructive) {
                    Task { await model.purgeAndReset() }
                }
                .disabled(resetConfirmation != "RESET")
            } message: {
                Text("Permanently erase private media, keys, temporary files and settings? This cannot be undone. Photos is unaffected.")
            }
        }
    }

    private var authorizationLabel: String {
        switch model.authorizationStatus {
        case .authorized: "Full access"
        case .limited: "Limited access"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }

    private var selectedFormat: GalleryOutputFormat {
        GalleryOutputFormat(rawValue: model.shareOutputFormat) ?? .heic
    }
}
