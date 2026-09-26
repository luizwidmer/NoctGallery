import SwiftUI

struct GalleryDuressPracticeView: View {
    @State private var practice = GalleryDuressPractice()
    @State private var action = GalleryDuressAction.retainDecoys
    @State private var retained: Set<Int> = [0]
    @State private var pin = ""
    @State private var result: GalleryPracticeResult?
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                Label("Practice with sample media", systemImage: "graduationcap")
                Text("Your gallery, PINs and security keys are never used or changed here.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let result {
                Section(result.action == .reset ? "Finish Onboarding" : "Private Gallery") {
                    if result.remainingSamples.isEmpty { Text("The practice gallery is empty.") }
                    else { sampleRow(indices: result.remainingSamples, selectable: false) }
                    Text(result.action == .reset ? "A real reset returns you to onboarding." : "Only the selected samples remain.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Checked in the practice vault") {
                    check("New encryption key", passed: result.mediaKeyChanged)
                    check("Practice duress PIN is now the only unlock", passed: result.replacementPINWorks && result.onlyPINRequired)
                    check("Previous PIN rejected", passed: result.oldPINRejected)
                    Button("Practice Again") { self.result = nil; pin = "" }
                }
            } else {
                Section {
                    Picker("Action", selection: $action) {
                        ForEach(GalleryDuressAction.allCases) { Text($0.title).tag($0) }
                    }
                    sampleRow(indices: [0, 1, 2], selectable: action == .retainDecoys)
                    if action == .retainDecoys { Text("Tap the samples to keep.").font(.footnote).foregroundStyle(.secondary) }
                } header: { Text("Disposable gallery") }
                Section {
                    NoctGalleryMark().frame(maxWidth: .infinity).padding(.vertical, 12)
                    GalleryPINField(title: "Practice PIN", text: $pin)
                        .accessibilityIdentifier("practice.pin")
                    Button("Unlock Sample Gallery") { run() }
                        .disabled(!GalleryPINVerifier.isValid(pin) || (action == .retainDecoys && retained.isEmpty))
                        .accessibilityIdentifier("practice.run")
                    if busy { ProgressView("Running practice…") }
                    if let error { Text(error).foregroundStyle(.red) }
                } header: { Text("Practice lock screen") } footer: {
                    Text("Enter \(GalleryDuressPractice.practicePIN). This uses Gallery’s duress logic on the samples, before any biometric or key check.")
                }
            }
        }
        .disabled(busy)
        .navigationTitle("Practice Duress").navigationBarTitleDisplayMode(.inline)
        .onDisappear { task?.cancel(); task = nil; pin = ""; result = nil }
    }

    private func sampleRow(indices: [Int], selectable: Bool) -> some View {
        HStack(spacing: 12) {
            ForEach(indices, id: \.self) { index in
                Button {
                    if retained.contains(index) { retained.remove(index) } else { retained.insert(index) }
                } label: {
                    VStack(spacing: 6) {
                        if let data = try? GalleryDuressPractice.sampleImage(index: index), let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 140)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(alignment: .topTrailing) {
                                    if selectable { Image(systemName: retained.contains(index) ? "checkmark.circle.fill" : "circle").foregroundStyle(.white).padding(6) }
                                }
                        }
                        Text("Sample \(index + 1)").font(.caption)
                    }
                }.buttonStyle(.plain).disabled(!selectable)
            }
        }.padding(.vertical, 6)
    }

    private func check(_ title: String, passed: Bool) -> some View {
        Label(title, systemImage: passed ? "checkmark.circle.fill" : "exclamationmark.triangle")
            .foregroundStyle(passed ? .green : .red)
    }

    private func run() {
        busy = true; error = nil
        let entered = pin
        pin = ""
        task = Task {
            defer { busy = false }
            do {
                let receipt = try await practice.run(action: action, retainedSamples: retained, enteredPIN: entered)
                guard !Task.isCancelled else { return }
                result = receipt
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
