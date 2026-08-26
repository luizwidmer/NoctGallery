import SwiftUI

struct GallerySettingsView: View {
    @EnvironmentObject private var model: GalleryViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("share.outputFormat") private var outputFormat = GalleryOutputFormat.heic.rawValue
    @AppStorage("share.maximumDimension") private var maximumDimension = 8_192
    @AppStorage("share.lossyQuality") private var lossyQuality = 0.90

    var body: some View {
        NavigationStack {
            Form {
                Section("Sanitized shares") {
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
                        Text("Noct Gallery reads the selected original on demand, rebuilds a bounded image from decoded pixels, and hands the share sheet a protected temporary file. Apple Photos remains the source of truth.")
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

                Section("About") {
                    LabeledContent("Version", value: "0.1.0")
                    Text("Noct Gallery contains no analytics, tracking SDK, advertising SDK, or application network client. PhotoKit may access iCloud when an original is not stored locally.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(NoctGalleryTheme.background(for: colorScheme))
            .navigationTitle("Settings")
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
