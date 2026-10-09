# Smart Search, sensitive-area detection and blur — October 9, 2026

The later [search language and smart-feature defaults record](Validation-2026-10-09-SearchLanguage.md) adds editable synonyms, real local phrase interpretation, off-by-default controls and Apple Intelligence device gating, with the expanded final suite.

Local version **0.5.0 (13)** adds opt-in object/scene tags, expanded privacy detection and blurred exports. Smart Albums, backups, device transfer and Noctweave sharing are excluded. This release has not been uploaded or submitted; the prior 0.4.0 submission is separate.

## Executed checks

| Check | Result |
| --- | --- |
| Native iOS app on Apple Silicon Mac, full suite | 96 passed; zero failures or skips. |
| Final native Smart Search suite, including the new diverse-object matrix | 7 passed; zero failures or skips. This adds one test to the earlier full suite, for 97 distinct tests verified across the two runs. |
| iPhone 17, iOS 26.5 Simulator | 93 passed; two native-model tests explicitly excluded. |
| Final iPhone photo/buffer blur checks | 6 passed, including the added partial-alpha regression. |
| iPad Pro 13-inch (M5), iOS 26.5 Simulator | 94 passed; two native-model tests explicitly excluded. This includes the partial-alpha regression. |
| Release build for generic iOS, signing disabled | Application and embedded share extension built successfully. Both plists report 0.5.0 (13). |
| Release bundle resource inspection | No test photographs, classification JSON or test bundles in the application or extension. |

The new diverse-object matrix was added after the full suites and then executed in the focused native suite. Simulator recognition exclusions are explained below; a zero skipped-test count in the result summary does not include tests excluded through `-skip-testing`.

## Real classification and context queries

`GallerySmartSearchTests` calls the production classifier afresh on eight fictional photographs, then searches a `GalleryOrganization` containing only the returned AI tags. Captions, OCR, notes and manual tags are empty, so matching cannot come from fixture filenames or descriptions.

| Photograph | Positive queries | Examples that must not match | Selected actual classifier score |
| --- | --- | --- | --- |
| Dog on grass | dog, puppy, cachorro, show me my dog | bicycle, headphones, laptop, coffee | dog: 0.960 |
| Bicycle | bicycle, bike, bicicleta | dog, headphones, coffee, laptop | bicycle: 0.961 |
| Open laptop | laptop, computer, computador | dog, bicycle, coffee, headphones | laptop: 0.899 |
| Cafe table | coffee, café, croissant, coffee with croissant | headphones, dog, bicycle, sunglasses | coffee: 0.968; croissant: 0.958 |
| Fictional itinerary beside sunglasses | sunglasses | headphones, coffee, dog, bicycle | sunglasses: 0.602 |
| Mountain lake | lake, water, mountains, lake with mountains | headphones, laptop, coffee, dog | lake: 0.681; mountain: 0.451 |
| Headphones beside a plant | headphones, plant, headphones with plant | dog, coffee, bicycle, laptop | headphones: 0.955; plant: 0.284 |
| Fictional cafe portrait | people, plant, people with plant | headphones, dog, bicycle, laptop | people: 0.918; plant: 0.700 |

All **25 positive** and **32 unrelated** queries passed. Scores are classifier outputs, not an estimate of general accuracy. Background objects can contribute useful tags; these photos are a regression sample and do not establish accuracy on every collection. Recognition can miss or mislabel objects, and AI tags can be removed or refreshed in photo details.

The actual label arrays are preserved as a `diverse-object-classifications` XCTest attachment. [Media provenance and exact generation prompts](AIValidationMedia.md) are checked in with the test photos. The files belong to the test bundle only.

Other Smart Search checks verify aliases and mixed metadata queries; legacy encrypted-index decoding; tag validation and bounds; encrypted persistence across lock/reopen; opt-out clearing AI tags while preserving originals and user metadata; rejection of old sessions, deleted photos, changed crops and results superseded by a removed tag; automatic tagging after import; and cancellation when locking or disabling search.

## Detection and encoded blur

Actual Vision tests find the fictional portrait's face, read small rendered text with accurate OCR, distinguish sensitive text from ordinary text and detect a Core Image generated QR code. Detection options cover faces, all/sensitive/off text, codes and balanced/thorough sensitivity. Results contain bounded rectangles and categories; recognized text and code payloads are discarded. Deduplication and the 100-area limit are tested.

Photo and pixel-buffer checks verify reduced checkerboard detail, nonblack blurred pixels, unchanged pixels outside selected areas, unchanged buffer padding, moving keyframes, invalid-area rejection and replacement of partially transparent pixels without blending original detail back in. Video tests decode freshly encoded output to check stationary/moving blur, trimming against source timestamps, rotation and preserved pixels outside the selected area. Existing tracking, selective audio mute, original preservation, metadata removal, encrypted inbox and duress checks also pass.

Blur retains coarse color and shape. Inspect the complete encoded output before sharing, especially moving regions and detections that were accepted automatically.

## Rendered inspection

The isolated review app renders 16 native screens on each platform, captured as XCTest attachments. The new Smart Search settings, object-search result, face-blur editor and actual blurred export were visually inspected on iPhone and iPad; the native Mac equivalents were also inspected. Text wraps within the phone sheet, tablet controls remain aligned, the headphone query shows the recognized photo, and the reviewed exported face region contains blurred color rather than a black cover. This verifies sampled rendered states, not every gesture, accessibility size or camera/hardware workflow.

The review bundle uses its own bundle identifier, App Group, keys and disposable vault. Fixture installation is gated to the review bundle on Simulator or iOS-on-Mac; it never changes the production vault or Photos library. Fixture tests remove their vault and review credentials after capture.

## Platform limits and evidence

The installed iOS 26.5 Simulator classifier returned incorrect moon/night-sky labels for unrelated input photos across CGImage, CIImage and pixel-buffer paths. Its recognition output is therefore not used as accuracy evidence. The native iOS-on-Mac app uses the same production classifier with the device compute path and correctly classifies the photos above. Native import/index/lock/disable checks also passed there. Simulator screenshots use genuine labels captured by the native fixture run; their pre-indexed JSON is never read by the functional classifier tests or shipping app.

Simulator barcode revisions 3/4 did not decode the generated QR fixture; the Simulator path selects supported revision 2. Device builds retain Vision's current default revision. Face detection and OCR passed on both Simulator and native paths.

The paired physical iPhone was locked and Xcode could not enable development services, so physical iPhone/iPad inference, camera capture, Face ID, USB keys and cross-application share-extension handoff remain unverified. The unsigned Release build confirms compilation and packaging, not distribution signing or installation. Existing SDK/YubiKit warnings and a native full-suite main-thread runtime warning remain recorded in the logs.

Result summaries, full final result bundles, build logs, actual classifier output and reviewed screenshots are preserved privately under `PICCP Project/ReleaseArtifacts/NoctGallery-0.5.0-2026-10-09/`; they are not tracked. Task-specific build products and installed review apps are removed after preserving the evidence, and existing Simulators are retained.

## Reproduction

Use the native Mac destination listed by `rtk proxy xcodebuild -project NoctGallery.xcodeproj -scheme NoctGallery -showdestinations`. Assign its ID to `NOCTGALLERY_MAC_ID`, then run:

```sh
rtk proxy xcodebuild -project NoctGallery.xcodeproj -scheme NoctGallery \
  -destination "platform=macOS,id=$NOCTGALLERY_MAC_ID" \
  -derivedDataPath .build/smart-search-mac \
  -parallel-testing-enabled NO -allowProvisioningUpdates \
  GALLERY_APP_BUNDLE_IDENTIFIER=com.luizwidmer.NoctGallery.gallery-features.visual-review \
  GALLERY_DISPLAY_NAME='Gallery Feature Review' test
```

For just the final object/index checks, add `-only-testing:NoctGalleryTests/GallerySmartSearchTests`. The review app is disposable; do not use it for personal media.

On the affected iOS 26.5 Simulator runtime, explicitly exclude these three native-model tests from a full run of the final source. The first two were the exclusions used in the earlier recorded Simulator suites; the third is the subsequently added native object matrix:

```sh
-skip-testing:NoctGalleryTests/GallerySmartSearchTests/testRealOnDeviceClassifierFindsHeadphonesWithoutTextOrManualTags
-skip-testing:NoctGalleryTests/GallerySmartSearchTests/testNewImportsAreAutomaticallyTaggedAndLockCancelsRefresh
-skip-testing:NoctGalleryTests/GallerySmartSearchTests/testRealClassifierFindsDiverseObjectsAndRejectsUnrelatedContext
```

Run all three without exclusions in the native iOS-on-Mac app or on an unlocked provisioned iPhone/iPad. Do not substitute stored reference labels for the functional tests.
