import SwiftUI

struct GalleryRecentlyDeletedView: View {
    @EnvironmentObject private var model: GalleryViewModel
    @State private var selected: Set<String> = []
    @State private var confirmingEmpty = false
    var body: some View {
        List {
            Section {
                Text("Deleted items stay encrypted for up to seven days. Expired items are removed when Gallery opens or returns to the foreground while unlocked. Duress and Purge/Reset bypass recovery.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if model.recentlyDeletedItems.isEmpty {
                ContentUnavailableView("No Deleted Items", systemImage: "trash", description: Text("Items appear here only when Recently Deleted is enabled before deletion."))
            } else {
                Section {
                    ForEach(model.recentlyDeletedItems) { item in
                        Button {
                            if selected.contains(item.id) { selected.remove(item.id) }
                            else if selected.count < 500 { selected.insert(item.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(item.id) ? NoctGalleryTheme.accent : Color.secondary)
                                GalleryDeletedThumbnail(item: item).frame(width: 60, height: 60).clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading) {
                                    Text(item.asset.mediaTitle).foregroundStyle(.primary)
                                    Text(item.asset.dateLabel).font(.caption).foregroundStyle(.secondary)
                                    Text("\(item.daysRemaining()) days remaining").font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }.padding(.vertical, 4)
                        }.buttonStyle(.plain).accessibilityAddTraits(selected.contains(item.id) ? .isSelected : [])
                    }
                }
                Section {
                    Button("Restore \(selected.count) Selected", systemImage: "arrow.uturn.backward") {
                        let ids = selected; Task { await model.restoreRecentlyDeleted(ids); selected = [] }
                    }.disabled(selected.isEmpty)
                    Button(selected.isEmpty ? "Empty Recently Deleted" : "Delete \(selected.count) Selected Permanently", systemImage: "trash", role: .destructive) { confirmingEmpty = true }
                }
            }
        }
        .disabled(model.isOrganizing)
        .navigationTitle("Recently Deleted")
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button(selected.isEmpty ? "Select Up to 500" : "Deselect All") {
                selected = selected.isEmpty ? Set(model.recentlyDeletedItems.prefix(500).map(\.id)) : []
            }.disabled(model.recentlyDeletedItems.isEmpty)
        } }
        .task { await model.refreshRecentlyDeleted() }
        .onChange(of: model.recentlyDeletedItems.map(\.id)) { _, ids in selected.formIntersection(ids) }
        .confirmationDialog("Permanently delete these items?", isPresented: $confirmingEmpty, titleVisibility: .visible) {
            Button("Delete Permanently", role: .destructive) {
                let ids = selected.isEmpty ? nil : selected
                Task { await model.permanentlyDeleteRecentlyDeleted(ids); selected = [] }
            }
        } message: { Text("This cannot be undone. Photos originals are unaffected.") }
    }
}

private struct GalleryDeletedThumbnail: View {
    @EnvironmentObject private var model: GalleryViewModel
    let item: GalleryDeletedItem
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: item.asset.kind == .photo ? "photo" : "video").frame(maxWidth: .infinity, maxHeight: .infinity).background(.quaternary) }
        }.accessibilityHidden(true)
            .task(id: model.privateGeneration) { image = await model.deletedThumbnail(for: item) }
            .onChange(of: model.privateGeneration) { _, _ in image = nil }
            .onDisappear { image = nil }
    }
}
