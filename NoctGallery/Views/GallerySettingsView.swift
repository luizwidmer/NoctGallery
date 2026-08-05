import SwiftUI

struct GallerySettingsView: View {
    @EnvironmentObject private var model: GalleryViewModel
    @Environment(\.openURL) private var openURL
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
                    Picker("Maximum edge", selection: $maximumDimension) {
                        Text("2,048 px").tag(2_048)
                        Text("4,096 px").tag(4_096)
                        Text("8,192 px").tag(8_192)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Lossy quality", value: lossyQuality.formatted(.percent.precision(.fractionLength(0))))
                        Slider(value: $lossyQuality, in: 0.65 ... 1.0, step: 0.01)
                    }
                    Text("PNG ignores the lossy quality value. HEIC falls back to JPEG if the current device cannot encode HEIC.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Storage") {
                    LabeledContent("Private media copies", value: "None")
                    LabeledContent("Source of truth", value: "Apple Photos")
                    Button("Clear Temporary Share Files", systemImage: "trash") {
                        Task { await model.purgeTemporaryExports() }
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
}
