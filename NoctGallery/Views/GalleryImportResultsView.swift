import SwiftUI

struct GalleryImportResultsView: View {
    @EnvironmentObject private var model: GalleryViewModel
    @Environment(\.dismiss) private var dismiss
    let report: GalleryImportReport
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("\(report.succeeded) of \(report.outcomes.count) imported", systemImage: report.succeeded == report.outcomes.count ? "checkmark.circle" : "tray")
                        .font(.headline)
                    Text("Imported files were verified in your encrypted gallery. Files in their original apps stay unchanged.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Files") {
                    ForEach(report.outcomes) { item in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: item.status == .imported ? "checkmark.circle.fill" : item.status == .cancelled ? "pause.circle" : "exclamationmark.circle")
                                .foregroundStyle(item.status == .imported ? Color.green : Color.secondary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.name).lineLimit(3)
                                Text(item.status == .imported ? "Imported and verified" : item.message ?? "Not imported")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4).accessibilityElement(children: .combine)
                    }
                }
                if report.succeeded != report.outcomes.count {
                    Section {
                        Button(report.incoming ? "Retry Pending Incoming Files" : "Retry Files That Were Not Imported") {
                            Task { if report.incoming { await model.importIncoming() } else { await model.importFiles(report.retryURLs) } }
                        }.disabled(model.isProcessing || (!report.incoming && report.retryURLs.isEmpty))
                        Text(report.incoming ? "Failed files remain in Incoming Shares until imported or discarded." : "Some file providers may ask you to select a file again if access has expired.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Import Results").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
