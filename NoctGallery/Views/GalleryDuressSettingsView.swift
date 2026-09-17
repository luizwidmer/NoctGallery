import SwiftUI

struct GalleryDuressSettingsView: View {
    @EnvironmentObject private var lock: GalleryLockController
    @EnvironmentObject private var model: GalleryViewModel
    @State private var action = GalleryDuressAction.reset
    @State private var pin = ""
    @State private var confirmation = ""
    @State private var selection: Set<String> = []
    @State private var showsConfirmation = false
    @State private var saved = false
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                Text("A duress PIN runs its action immediately from the lock screen, even before a security key or biometric check. Afterward, that PIN becomes the only unlock method.")
                Text("Actions permanently affect Gallery’s private storage. They cannot erase copies already shared, device snapshots, or originals in Apple Photos.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let active = lock.configuration?.duress, !active.isEmpty {
                Section("Enabled actions") {
                    ForEach(active) { credential in
                        HStack {
                            Label(credential.action.title, systemImage: "checkmark.shield")
                            Spacer()
                            Button("Remove", role: .destructive) { Task { await lock.removeDuress(credential.action) } }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
            Section {
                NavigationLink {
                    GalleryDecoyPicker(selection: $selection)
                } label: {
                    LabeledContent("Decoy photos & videos", value: "\(selection.count) selected")
                }
                if selection != (lock.configuration?.decoyIDs ?? []) {
                    Button("Save Decoy Selection") { Task { await lock.setDecoys(selection) } }
                }
                Text("Keep real private items as decoys. They remain fully usable after the action. Every unselected private item is removed and the storage encryption key is replaced.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Retained media") }
            Section("Set a duress PIN") {
                Picker("Action", selection: $action) {
                    ForEach(GalleryDuressAction.allCases) { Text($0.title).tag($0) }
                }
                Text(action == .reset
                    ? "Delete all private media, presets and settings, then show Finish Onboarding."
                    : "Delete all private media except your selected decoys, and clear presets and settings.")
                    .font(.footnote).foregroundStyle(.secondary)
                GalleryPINField(title: "Duress PIN", text: $pin).accessibilityIdentifier("duress.pin")
                GalleryPINField(title: "Confirm duress PIN", text: $confirmation).accessibilityIdentifier("duress.confirmPIN")
                Button("Enable Duress Action…", role: .destructive) { showsConfirmation = true }
                    .disabled(!GalleryPINVerifier.isValid(pin) || pin != confirmation || lock.isBusy
                        || (action == .retainDecoys && selection.isEmpty))
                    .accessibilityIdentifier("duress.enable")
                if saved { Label("Duress action saved", systemImage: "checkmark.circle").foregroundStyle(.green) }
                if let message = lock.message { Text(message).font(.callout).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Duress & Decoys").navigationBarTitleDisplayMode(.inline)
        .onAppear { if !loaded { selection = lock.configuration?.decoyIDs ?? []; loaded = true }; lock.message = nil }
        .onChange(of: pin) { _, _ in saved = false }
        .onDisappear { pin = ""; confirmation = "" }
        .confirmationDialog("Enable \(action.title)?", isPresented: $showsConfirmation, titleVisibility: .visible) {
            Button("Enable Action", role: .destructive) {
                let entered = pin
                Task {
                    if await lock.setDuress(action, pin: entered, ids: selection) {
                        pin = ""; confirmation = ""; saved = true
                    }
                }
            }
        } message: {
            Text("Entering this PIN on the lock screen will permanently remove \(action == .reset ? "all private media" : "every unselected private item") without another confirmation. It will replace your normal PIN, biometrics and key requirements. Saving this setting does not run it.")
        }
    }
}

private struct GalleryDecoyPicker: View {
    @EnvironmentObject private var model: GalleryViewModel
    @Binding var selection: Set<String>
    var body: some View {
        List {
            Section {
                if model.privateAssets.isEmpty {
                    ContentUnavailableView("No Private Media", systemImage: "photo.stack",
                        description: Text("Add private photos or videos, then choose the ones to retain."))
                }
                ForEach(model.privateAssets) { asset in
                    Button {
                        if selection.contains(asset.id) { selection.remove(asset.id) } else { selection.insert(asset.id) }
                    } label: {
                        HStack(spacing: 14) {
                            PhotoThumbnailView(asset: asset)
                                .frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(asset.kind.title).font(.headline)
                                Text(asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "Private item")
                                    .font(.caption).foregroundStyle(.secondary)
                                if asset.kind == .video { Text(asset.durationLabel).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                            }
                            Spacer()
                            Image(systemName: selection.contains(asset.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title2).foregroundStyle(selection.contains(asset.id) ? NoctGalleryTheme.accent : .secondary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityAddTraits(selection.contains(asset.id) ? .isSelected : [])
                }
            } footer: {
                Text("\(selection.count) items selected. Save the selection on the previous screen.")
            }
        }.navigationTitle("Choose Decoys").navigationBarTitleDisplayMode(.inline)
    }
}
