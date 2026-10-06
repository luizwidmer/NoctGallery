import SwiftUI

struct GalleryInboxView: View {
    @EnvironmentObject private var model: GalleryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDiscard = false
    var body: some View {
        Form {
            Section {
                Label("\(model.incomingCount) incoming files", systemImage: "tray.and.arrow.down")
                Text("Choose Save to NoctGallery in another app’s share sheet. Files wait here encrypted until you unlock Gallery and import them.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Import Incoming Files", systemImage: "square.and.arrow.down") { Task { await model.importIncoming() } }
                    .disabled(model.incomingCount == 0 || model.isProcessing || !model.privateUnlocked)
                if model.isProcessing { ProgressView(model.processingMessage ?? "Importing…") }
                if let error = model.inboxUnavailable { Text(error).foregroundStyle(.secondary) }
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            }
            Section {
                Button("Discard Incoming Files", role: .destructive) { confirmsDiscard = true }
                    .disabled(model.incomingCount == 0 || model.isProcessing)
            } footer: {
                Text("Imports preserve supported original bytes and metadata. Use Prepare to Share to create clean copies. Gallery cannot remove copies held by the source app.")
            }
        }
        .navigationTitle("Incoming Shares").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .task { await model.refreshInbox() }.refreshable { await model.refreshInbox() }
        .confirmationDialog("Discard all incoming files?", isPresented: $confirmsDiscard) {
            Button("Discard Incoming Files", role: .destructive) { Task { await model.discardIncoming() } }
        } message: { Text("Encrypted files waiting for import will be deleted. Your private gallery stays intact.") }
    }
}
