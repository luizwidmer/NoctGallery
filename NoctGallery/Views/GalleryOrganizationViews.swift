import SwiftUI

struct GalleryAlbumsView: View {
    @EnvironmentObject private var model: GalleryViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var editingID: UUID?
    @State private var naming = false
    @State private var deleting: GalleryAlbum?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.organization.albums) { album in
                        HStack {
                            Label(album.name, systemImage: "folder")
                            Spacer()
                            Text("\(model.organization.items.values.filter { $0.albumIDs.contains(album.id) }.count)")
                                .foregroundStyle(.secondary)
                            Menu {
                                Button("Rename") { editingID = album.id; name = album.name; naming = true }
                                Button("Delete Album", role: .destructive) { deleting = album }
                            } label: { Image(systemName: "ellipsis.circle").padding(6) }
                                .accessibilityLabel("Options for \(album.name)")
                        }
                    }
                    Button("New Album", systemImage: "folder.badge.plus") { editingID = nil; name = ""; naming = true }
                } footer: { Text("Albums and tags are encrypted with your private gallery. Deleting an album keeps its media.") }
            }
            .disabled(model.isOrganizing)
            .navigationTitle("Albums").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert(editingID == nil ? "New Album" : "Rename Album", isPresented: $naming) {
                TextField("Album name", text: $name).autocorrectionDisabled()
                Button("Cancel", role: .cancel) { }
                Button("Save") { Task { await model.saveAlbum(id: editingID, name: name) } }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 80)
            }
            .confirmationDialog("Delete album?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Delete Album", role: .destructive) {
                    if let id = deleting?.id { Task { await model.deleteAlbum(id) } }
                    deleting = nil
                }
            } message: { Text("The photos and videos stay in your private gallery.") }
        }
    }
}

struct GalleryOrganizeView: View {
    @EnvironmentObject private var model: GalleryViewModel
    @Environment(\.dismiss) private var dismiss
    let ids: Set<String>
    @State private var tags = ""
    @State private var showsAlbums = false
    @State private var loaded = false
    @State private var confirmsTags = false
    @State private var savedTags = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Albums") {
                    ForEach(model.organization.albums) { album in
                        let count = ids.filter { model.organization.items[$0]?.albumIDs.contains(album.id) == true }.count
                        Button {
                            Task { await model.organize(ids, edit: count == ids.count ? .removeFromAlbum(album.id) : .addToAlbum(album.id)) }
                        } label: {
                            HStack {
                                Text(album.name).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: count == ids.count ? "checkmark.circle.fill" : count > 0 ? "minus.circle.fill" : "circle")
                            }
                        }
                        .accessibilityValue(count == ids.count ? "Included" : count > 0 ? "Some items" : "Not included")
                    }
                    Button("Manage Albums", systemImage: "folder.badge.plus") { showsAlbums = true }
                }
                Section {
                    TextField("travel, family, documents", text: $tags, axis: .vertical)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .accessibilityLabel("Tags separated by commas")
                    Button(ids.count == 1 ? "Save Tags" : "Replace Tags on \(ids.count) Items") {
                        if ids.count > 1 { confirmsTags = true } else { saveTags() }
                    }.disabled((try? GalleryOrganization.tags(from: tags)) == nil)
                    if savedTags { Label("Tags saved", systemImage: "checkmark.circle").foregroundStyle(.green) }
                } header: { Text("Tags") } footer: { Text("Up to 32 tags, separated by commas; 40 characters each. Leave empty to remove tags.") }
            }
            .disabled(model.isOrganizing)
            .navigationTitle(ids.count == 1 ? "Albums & Tags" : "Organize \(ids.count) Items")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear {
                if !loaded {
                    if ids.count == 1, let id = ids.first { tags = model.organization.items[id]?.tags.joined(separator: ", ") ?? "" }
                    loaded = true
                }
            }
            .sheet(isPresented: $showsAlbums) { GalleryAlbumsView() }
            .onChange(of: tags) { _, _ in savedTags = false }
            .confirmationDialog("Replace tags on every selected item?", isPresented: $confirmsTags) {
                Button("Replace Tags") { saveTags() }
            }
        }
    }

    private func saveTags() {
        guard let values = try? GalleryOrganization.tags(from: tags) else { return }
        Task {
            model.errorMessage = nil
            await model.organize(ids, edit: .tags(values))
            savedTags = model.errorMessage == nil
        }
    }
}
