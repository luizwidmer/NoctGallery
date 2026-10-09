# Search language and smart-feature defaults — October 9, 2026

This record extends the [Smart Search, detection and blur validation](Validation-2026-10-09-SmartSearch.md) for local **0.5.0 (13)**. It covers editable synonyms, local phrase interpretation, explicit opt-ins and device availability. The candidate has not been uploaded or submitted to App Store Connect.

## Defaults and availability

Tagging, AI phrase interpretation and text indexing are off by default. Missing preferences in existing encrypted vaults mean off. Tagging and phrase interpretation require separate opt-ins; enabling tagging never enables the language model. Phrase interpretation requires tagging enabled first.

| Apple Intelligence state | Smart Search UI | Background tagging and AI inference |
| --- | --- | --- |
| Device not eligible | Hidden from Settings, Library Tools, empty-search actions and photo tag controls | Blocked |
| Supported, Apple Intelligence off | Gray and disabled; Settings explains how to enable Apple Intelligence | Blocked |
| Supported, local model not ready | Gray and disabled; Settings explains model readiness | Blocked |
| Available | Visible; switches initially off | Requires the corresponding explicit opt-in |

The production mapping uses Apple's [SystemLanguageModel availability](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel), rather than device names. Foreground activation and private-gallery unlock recheck it. Runtime entry points, tagging iterations and query publication also enforce availability and unlock state. Saved opt-ins cannot start work while Apple Intelligence is unavailable. Losing availability cancels and awaits tagging/interpretation and discards the transient query plan and vocabulary, while retaining saved preferences and encrypted tags. Existing tags still match ordinary searches until tagging is disabled and removes them.

Six additional regression tests cover fresh/legacy defaults, imports without automatic tagging, independent encrypted query opt-in across lock/reopen, rejected opt-ins on unsupported or inactive devices, saved opt-ins on unavailable devices, and cancellation/late-result rejection when availability changes. Controlled providers exercise these states without changing system settings. Actual native model tests use the production availability provider and real inference.

## Final execution

| Check | Result |
| --- | --- |
| Complete native iOS app on Mac suite | 114 passed, zero failures or skips |
| iPhone 17 Simulator focused suite | 19 passed, one real-model test explicitly skipped, zero failures |
| iPad Pro 13-inch Simulator focused suite | 19 passed, one real-model test explicitly skipped, zero failures |
| Unsigned iOS Release app and import extension | Build succeeded; both report 0.5.0 (13) |
| Release resources | No test photographs, classification JSON or test bundles in either shipping bundle |

The focused Simulator suites include query interpretation/default/availability tests, synonyms, duress organization cleanup and rendered fixtures. They do not select the three classifier tests excluded on this installed Simulator runtime. The native full suite runs every classifier and language-model test.

## Real AI search and editable synonyms

The native language-model test classifies eight fictional photographs afresh with the production Vision classifier. It supplies only the resulting bounded English labels to the production query interpreter. The organization has no synonym groups, captions, notes or OCR, so matching cannot come from aliases, filenames or manual metadata.

Twelve queries cover headphones described by their use, Portuguese sunglasses, dogs, bicycles, coffee with croissants, mountain lakes, a portable computer described by its use, English/Portuguese alternatives and English/Portuguese exclusions. Every required positive result and unrelated negative result passed. Both coffee/croissant subjects must be required; dog/bicycle alternatives share one OR group; bicycle queries exclude people. Absent electric-guitar and spaceship requests produce no unrelated matches or are rejected in favor of literal search. Actual plans are preserved as an XCTest JSON attachment.

The model maps subject phrases to actual English labels. Bounded English/Portuguese operators combine them deterministically. Mixed AND/OR expressions fall back to literal search. Actions, spatial relationships, dates, colors and other details are not verified by tags; the UI always explains this matching scope. This corpus is a regression sample, not a general accuracy estimate.

Three synonym tests verify immediate add/edit/delete/restore behavior, normalized conflicts and bounds, encrypted persistence, stale-session/group rejection and preservation of originals and user metadata. Existing keyword matches and custom synonyms take priority over AI; explicit context such as “headphones vacation” cannot be broadened to a context-free result. Disabling phrase interpretation discards its vocabulary and plan while retaining ordinary search.

## Rendered verification

The isolated review app captures 25 native Mac screens and 24 each on iPhone and iPad. These include the synonym list/editor, object results, default-off switches, unsupported-device Settings, Apple Intelligence off in Settings and the Smart Search page, and model-not-ready controls. Disabled toggles and the Settings entry use explicit secondary text color. Sampled phone/tablet screens are inspected for wrapping, clipping, alignment and hidden/gray states. Existing generated photographic media remains in gallery/share/blur captures; availability-only screens use fresh disposable preferences.

The Simulator's production Smart Search availability is unsupported because its Foundation Models assets cannot run inference reliably. Layout fixtures inject readiness or other availability states only for rendering; their interpreter still delegates to the real model and cannot manufacture functional AI results. Classifier reference JSON is used only for Simulator layout, as explained in the earlier validation. Actual accuracy is verified on the native compute path.

## Limits and evidence

The real ready state is verified on the eligible native Mac. Unsupported, disabled, not-ready states and state changes are verified with controlled providers and rendered UI. Physical iPhone/iPad inference and actual system-setting transitions on those devices remain unverified. Simulator tests explicitly skip real language-model inference. The unsigned release build verifies compilation and packaging, not distribution signing, upload or App Store approval. Existing SDK/YubiKit and native runtime warnings remain in the logs.

Final result bundles, logs, summaries, query plans, classifications, reviewed screenshots, source hashes and packaging inspection are preserved privately under `PICCP Project/ReleaseArtifacts/NoctGallery-0.5.0-2026-10-09/search-language/`. Earlier baseline evidence has its own source manifest. Task build products and temporary marketing resources are removed after preservation; the existing Simulators are retained and their review app is uninstalled. Fictional classifier photographs remain as test-only resources with [documented provenance](AIValidationMedia.md).

Run the complete suite with the native destination and isolated review bundle command in the earlier validation. For focused checks add `-only-testing:NoctGalleryTests/GalleryQueryInterpretationTests`, `-only-testing:NoctGalleryTests/GallerySearchAliasTests`, `-only-testing:NoctGalleryTests/GalleryVisualFixtureTests`, and `-only-testing:NoctGalleryTests/GalleryLibraryUpgradeTests/testDuressDropsNotesTextAndRecipesWhileKeepingSelectedMedia`. The real model test needs a supported device with Apple Intelligence enabled and ready.
