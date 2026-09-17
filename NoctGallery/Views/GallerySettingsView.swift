import SwiftUI

struct GallerySettingsView: View {
    @EnvironmentObject private var model: GalleryViewModel
    @EnvironmentObject private var lock: GalleryLockController
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("share.outputFormat") private var outputFormat = GalleryOutputFormat.heic.rawValue
    @AppStorage("share.maximumDimension") private var maximumDimension = 8_192
    @AppStorage("share.lossyQuality") private var lossyQuality = 0.90
    @State private var showsResetConfirmation = false
    @State private var resetConfirmation = ""

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
                    Text("Private captures are encrypted on this device and excluded from backups. They are never automatically added to Photos.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Photo shares") {
                    Picker("Output format", selection: $outputFormat) {
                        ForEach(GalleryOutputFormat.allCases) { format in
                            Text(format.title).tag(format.rawValue)
                        }
                    }
                    DisclosureGroup("Advanced Share Defaults") {
                        Picker("Maximum edge", selection: $maximumDimension) {
                            Text("2,048 px").tag(2_048)
                            Text("4,096 px").tag(4_096)
                            Text("8,192 px").tag(8_192)
                        }
                        if selectedFormat != .png {
                            VStack(alignment: .leading, spacing: 8) {
                                LabeledContent("Lossy quality", value: lossyQuality.formatted(.percent.precision(.fractionLength(0))))
                                Slider(value: $lossyQuality, in: 0.65 ... 1.0, step: 0.01)
                            }
                        }
                        Text("HEIC falls back to JPEG only when this device cannot encode HEIC.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Privacy & storage") {
                    DisclosureGroup("How sharing works") {
                        Text("Photos and videos are decoded and rebuilt into protected temporary copies for sharing. Video exports use H.264 and AAC, up to 1080p at 30 fps. Originals in Photos are never modified.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if model.hasTemporaryShareFiles {
                        Button("Clear Temporary Share Files", systemImage: "trash") {
                            Task { await model.purgeTemporaryExports() }
                        }
                    }
                    Text("Temporary files use complete file protection, are excluded from backup, and are removed after the share sheet closes.")
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
                    Text("Permanently delete the private gallery and its encryption key, temporary files, presets, and settings. Your Photos originals and copies already shared remain unchanged.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section { AppSupportCard().listRowInsets(EdgeInsets()) }

                Section("About") {
                    LabeledContent("Version", value: "0.1.0")
                    Text("No analytics, advertising or tracking. PhotoKit may download iCloud media. Place searches and map tiles use Apple Maps; the app never requests your current GPS location.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(NoctGalleryTheme.background(for: colorScheme))
            .navigationTitle("Settings")
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
                Text("This permanently deletes your private photos and videos, their encryption key, temporary files, presets and settings. It cannot be undone. Your Photos library is not deleted.")
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
        GalleryOutputFormat(rawValue: outputFormat) ?? .heic
    }
}
