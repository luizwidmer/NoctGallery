import SwiftUI

struct GallerySmartSearchView: View {
    @EnvironmentObject private var model: GalleryViewModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            if model.showsSmartSearch {
                Section {
                    Text(model.queryInterpreterAvailability.message).font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Toggle("Find objects and scenes", isOn: Binding(get: { model.organization.visualSearchEnabled == true }, set: { value in Task { await model.setVisualSearch(value) } }))
                        .disabled(controlsDisabled)
                        .foregroundStyle(controlsDisabled ? Color.secondary : Color.primary)
                        .accessibilityIdentifier("smart-search.tagging")
                    Text("AI recognizes what is in your photos on this device. Search for headphones, a dog or a beach without tagging each photo yourself.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Tags stay encrypted in your private gallery and are available only while unlocked. Turning this off removes all AI tags. Your own tags and notes stay.")
                        .font(.footnote).foregroundStyle(.secondary)
                } header: { Label("Smart Search", systemImage: "sparkle.magnifyingglass") }
                Section("Search wording") {
                    Toggle("Interpret search phrases with AI", isOn: Binding(get: { model.organization.aiQueryInterpretationEnabled == true }, set: { value in
                        Task { await model.setAIQueryInterpretation(value) }
                    }))
                        .disabled(controlsDisabled || model.organization.visualSearchEnabled != true)
                        .foregroundStyle(controlsDisabled || model.organization.visualSearchEnabled != true ? Color.secondary : Color.primary)
                        .accessibilityIdentifier("smart-search.phrases")
                    if model.organization.visualSearchEnabled != true {
                        Text("Enable photo tagging first to use AI phrase search.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("Your current phrase and recognized tag names are interpreted on this device and are not saved as search history. Photos and notes aren't given to the language model. The search shows the interpreted subjects.")
                        .font(.footnote).foregroundStyle(.secondary)
                    NavigationLink("Search Synonyms") { GallerySearchAliasesView() }.disabled(controlsDisabled)
                }
                if model.organization.visualSearchEnabled == true {
                    Section("Photo tagging") {
                        LabeledContent("Tagged photos", value: "\(model.privateAssets.filter { $0.kind == .photo && model.organization.items[$0.id]?.visualTags != nil }.count)")
                        LabeledContent("Waiting to be tagged", value: "\(model.untaggedPhotoCount)")
                        if model.isTagging {
                            ProgressView(model.analysisProgress ?? "Recognizing photos…")
                            Button("Pause Tagging") { model.cancelAnalysis() }
                        } else if model.untaggedPhotoCount > 0 {
                            Button(model.visualTaggingPaused ? "Resume Tagging" : "Tag Remaining Photos", systemImage: "sparkles") { model.indexVisualTags() }
                                .disabled(controlsDisabled || model.isAnalyzing)
                        }
                        Text("Existing and newly imported photos are tagged while Gallery is unlocked. Recognition can miss objects or suggest incorrect tags. Open a photo to review or remove its AI tags.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let error = model.errorMessage { Section { Text(error).foregroundStyle(.red) } }
                Section {
                    NavigationLink("Search text inside photos") { GalleryTextSearchView() }
                }
            }
        }
        .navigationTitle("Smart Search").navigationBarTitleDisplayMode(.inline)
        .task {
            await model.refreshSmartFeatureAvailability()
            if !model.privateUnlocked { _ = await model.unlockPrivate() }
        }
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    private var controlsDisabled: Bool {
        !model.smartFeaturesAvailable || !model.privateUnlocked || model.isOrganizing || model.isResetting || model.isUpdatingVisualSearch
    }
}
