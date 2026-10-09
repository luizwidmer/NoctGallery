import SwiftUI

struct GallerySearchAliasesView: View {
    @EnvironmentObject private var model: GalleryViewModel
    @State private var editor: Editor?
    @State private var deleting: GallerySearchAliasGroup?
    @State private var restoresDefaults = false
    private struct Editor: Identifiable {
        let id = UUID()
        let group: GallerySearchAliasGroup
        let isNew: Bool
    }

    var body: some View {
        List {
            Section {
                ForEach(model.organization.effectiveSearchAliasGroups) { group in
                    Button {
                        editor = .init(group: group, isNew: false)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(group.terms.first ?? "Synonyms").foregroundStyle(Color.primary)
                                Text(group.terms.dropFirst().joined(separator: ", "))
                                    .font(.footnote).foregroundStyle(Color.secondary).multilineTextAlignment(.leading)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Color.secondary)
                        }
                    }
                    .swipeActions(allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) { deleting = group }
                    }
                    .contextMenu {
                        Button("Edit") { editor = .init(group: group, isNew: false) }
                        Button("Delete", role: .destructive) { deleting = group }
                    }
                }
                Button("Add Synonym Group", systemImage: "plus") { editor = .init(group: .init(terms: []), isNew: true) }
                    .disabled(model.organization.effectiveSearchAliasGroups.count >= 100)
            } footer: {
                Text("Each group links an AI tag to words you search for. For example: sunglasses, shades, óculos de sol. Changes work immediately with existing tags; your photos do not need to be tagged again.")
            }
            if let error = model.errorMessage { Section { Text(error).foregroundStyle(.red) } }
            Section {
                Button("Restore Default Synonyms") { restoresDefaults = true }
            } footer: {
                Text("Your synonym groups stay encrypted in your private gallery. Removing a group keeps every photo and AI tag; recognized tag names remain searchable.")
            }
        }
        .disabled(model.isOrganizing || !model.privateUnlocked || model.isResetting)
        .navigationTitle("Search Synonyms").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editor) { request in
            NavigationStack { GallerySearchAliasEditor(group: request.group, isNew: request.isNew) }
        }
        .confirmationDialog("Delete this synonym group?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete Group", role: .destructive) {
                if let group = deleting { Task { _ = await model.editSearchAliases(.delete(group.id)) } }
                deleting = nil
            }
        }
        .confirmationDialog("Restore default synonyms?", isPresented: $restoresDefaults) {
            Button("Restore Defaults", role: .destructive) { Task { _ = await model.editSearchAliases(.restoreDefaults) } }
        } message: { Text("This replaces your synonym groups with the built-in groups. Your photos and tags stay.") }
        .onChange(of: model.privateGeneration) { _, _ in editor = nil; deleting = nil; restoresDefaults = false }
    }
}

struct GallerySearchAliasEditor: View {
    @EnvironmentObject private var model: GalleryViewModel
    @Environment(\.dismiss) private var dismiss
    let group: GallerySearchAliasGroup
    let isNew: Bool
    @State private var text: String
    @State private var error: String?
    init(group: GallerySearchAliasGroup, isNew: Bool) {
        self.group = group; self.isNew = isNew
        _text = State(initialValue: group.terms.joined(separator: ", "))
    }
    var body: some View {
        Form {
            Section {
                TextField("sunglasses, shades, óculos de sol", text: $text, axis: .vertical)
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .accessibilityLabel("Search synonyms separated by commas")
            } header: { Text("Equivalent terms") } footer: {
                Text("Include a recognized AI tag and your preferred names for it. Use 2–12 terms separated by commas, up to 80 characters each. A term can belong to one group.")
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle(isNew ? "New Synonym Group" : "Edit Synonyms").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    guard let terms = try? GallerySearchAliasGroup.parse(text) else { return }
                    var changed = group; changed.terms = terms
                    Task {
                        if await model.editSearchAliases(.save(changed, replacing: isNew ? nil : group.id)) { dismiss() }
                        else { error = model.errorMessage ?? "Unlock your gallery to save synonyms." }
                    }
                }.disabled((try? GallerySearchAliasGroup.parse(text)) == nil || model.isOrganizing || !model.privateUnlocked)
            }
        }
        .disabled(model.isOrganizing || !model.privateUnlocked)
        .onChange(of: text) { _, _ in error = nil }
        .onChange(of: model.privateUnlocked) { _, unlocked in if !unlocked { text = ""; error = nil; dismiss() } }
    }
}
