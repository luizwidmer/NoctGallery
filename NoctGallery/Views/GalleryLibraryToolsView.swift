import SwiftUI

struct GalleryStorageView: View {
    @EnvironmentObject private var model: GalleryViewModel
    private func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    var body: some View {
        List {
            Section("On this device") {
                LabeledContent("Items", value: "\(model.privateAssets.count)")
                LabeledContent("Original media", value: size(model.storageItems.values.reduce(0) { $0 + $1.mediaBytes }))
                LabeledContent("Encrypted items", value: size(model.storageItems.values.reduce(0) { $0 + $1.storedBytes }))
                LabeledContent("Playback & work files", value: size(model.scratchBytes))
                LabeledContent("Share copies", value: size(model.exportBytes))
                Button("Clear Temporary Share Copies", systemImage: "trash") { Task { await model.purgeTemporaryExports(); await model.refreshStorage() } }
                    .disabled(model.isProcessing || model.shareRequest != nil)
            }
            Section("Albums") {
                ForEach(model.organization.albums) { album in
                    let bytes = model.storageItems.values.filter { model.organization.items[$0.id]?.albumIDs.contains(album.id) == true }.reduce(0) { $0 + $1.mediaBytes }
                    LabeledContent(album.name, value: size(bytes))
                }
                Text("An item can belong to multiple albums. Album totals may overlap.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Largest items") {
                ForEach(GalleryLibraryQuery.sorted(model.privateAssets, by: .largest, sizes: model.storageItems).prefix(20)) { asset in
                    NavigationLink { AssetDetailView(asset: asset) } label: {
                        HStack {
                            PhotoThumbnailView(asset: asset).frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading) { Text(asset.mediaTitle); Text(asset.dateLabel).font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Text(size(model.storageItems[asset.id]?.mediaBytes ?? 0)).font(.caption)
                        }
                    }
                }
            }
        }
        .navigationTitle("Storage")
        .task { await model.refreshStorage() }.refreshable { await model.refreshStorage() }
    }
}

struct GalleryTextSearchView: View {
    @EnvironmentObject private var model: GalleryViewModel
    var body: some View {
        Form {
            Section {
                Toggle("Search text inside photos", isOn: Binding(get: { model.organization.textSearchEnabled == true }, set: { value in Task { await model.setTextSearch(value) } }))
                    .disabled(model.isAnalyzing)
                Text("Text recognition runs on this device. Recognized text is encrypted inside the vault and available only while unlocked. Turning this off removes the saved text index.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if model.organization.textSearchEnabled == true {
                Section {
                    LabeledContent("Indexed photos", value: "\(model.organization.items.values.filter { $0.recognizedText != nil }.count)")
                    Button("Read Text in Unindexed Photos", systemImage: "text.viewfinder") {
                        let ids = Set(model.privateAssets.filter { $0.kind == .photo && model.organization.items[$0.id]?.recognizedText == nil }.map(\.id))
                        model.indexText(ids: ids)
                    }.disabled(model.isAnalyzing)
                    Text("Reads up to 500 photos per run. Use the private library search to find recognized words.").font(.footnote).foregroundStyle(.secondary)
                    if model.isAnalyzing {
                        ProgressView(model.analysisProgress ?? "Reading…")
                        Button("Cancel") { model.cancelAnalysis() }
                    }
                    if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
                }
            }
        }
        .navigationTitle("Private Text Search")
    }
}

struct GalleryDuplicatesView: View {
    @EnvironmentObject private var model: GalleryViewModel
    var ids: Set<String>?
    @State private var scanned = false
    var body: some View {
        List {
            Section {
                Text("Compare original bytes and look for similar photos. Review each item before deleting; nothing is removed automatically.")
                    .font(.footnote).foregroundStyle(.secondary)
                Text("Checks up to 500 items and compares up to 300 photo thumbnails per run. Select items in the library to choose a specific batch.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Find Duplicates", systemImage: "square.on.square") { scanned = true; model.findDuplicates(ids: ids) }.disabled(model.isAnalyzing)
                if model.isAnalyzing {
                    ProgressView(model.analysisProgress ?? "Comparing…")
                    Button("Cancel") { model.cancelAnalysis() }
                } else if scanned && model.duplicateGroups.isEmpty { Text("No matches found in this batch.").foregroundStyle(.secondary) }
                if let error = model.errorMessage { Text(error).foregroundStyle(.red) }
            }
            ForEach(model.duplicateGroups) { group in
                let assets = group.itemIDs.compactMap { id in model.privateAssets.first { $0.id == id } }
                Section(group.exact ? "Identical original media" : "Similar photos — review manually") {
                    ForEach(assets) { asset in
                        NavigationLink { AssetDetailView(asset: asset, sequence: assets) } label: {
                            HStack {
                                PhotoThumbnailView(asset: asset).frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading) { Text(asset.mediaTitle); Text(asset.dateLabel).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Duplicates")
        .onDisappear { model.cancelAnalysis() }
    }
}
