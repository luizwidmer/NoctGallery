# Gallery feature validation — 2026-09-26

Scope: export review and permanent covers, video trim/mute, encrypted organization and batch actions, complete original-resource imports, and isolated duress practice. Encrypted backup/device transfer is excluded.

Subsequent UI change: at the user's request, both duress-practice navigation links were removed. The practice implementation and tests remain. The screenshots below record verification before the practice entry points were hidden.

## Automated evidence

- iPhone 17, iOS 26.5: 64 tests passed, zero failures (`.build/feature-tests-final-iphone.xcresult`).
- iPad (A16), iOS 26.5: 63 tests passed before the additional Vision suggestion test (`.build/feature-tests-ipad-2.xcresult`).
- The first run exposed an inspector type-bridging bug that skipped string properties. Explicit string/number/array handling fixed it; the inspector and full suite then passed.
- Vision initially could not create an inference context in Simulator. The simulator-only supported CPU path passed an OCR fixture test; physical devices retain Vision's normal device selection.
- Debug Simulator and unsigned Release builds for generic iOS succeeded after the final UI changes. Signing, archive upload and review submission were not performed.

Coverage includes released single-resource records, encrypted organization across reopen, missing-key and tamper rejection, per-component Live/RAW round trips and duress rekeying, corrupt-companion refusal before deletion, static-cover pixel placement after rotation, trim duration with/without audio, cancellation after a cleared sheet binding, batch failure cleanup, and both practice actions with replacement-PIN verification.

## Disposable UI fixtures

`GalleryVisualFixtureTests/testInstallDisposableVisualFixtures` runs only in a simulator bundle whose identifier ends with `.gallery-features.visual-review`. It installs generated images/video and an unprotected sample vault in that separate app. It cannot run in the production bundle, does not touch Photos, and is excluded from ordinary regression counts. No production fixture switch or unlock bypass is included in the app.

The existing iPhone 17 and iPad (A16) simulators were reused; no simulator was created or erased.

## Rendered and interactive verification

- iPhone: checked the private grid, album chips, favorite badges, Live Photo companion playback, organization editing and tag search. Adding `covered` to one sample returned exactly that item in search.
- iPhone: accepted a local text suggestion and drew a second cover. The actual export preview and native share-sheet thumbnail both contained the permanent covers. Inspected the output's dimensions, size, remaining metadata and removed fields. Closed without sending or saving a copy; the temporary directory was empty afterward.
- iPad: checked portrait grid and selection controls, a mixed photo/video batch using a saved metadata preset, and both items in export review. A three-second sample trimmed by 0.7 seconds produced a 2.3-second output with no audio. Audio removal/preservation on a sample containing audio is covered by the automated suite.
- iPad: ran Keep Selected Decoys in the isolated practice vault. The result showed only Sample 1, a new encryption key, the practice duress PIN as the sole unlock, and rejection of the previous sample PIN. All eight sample items in the separate review app's gallery remained present.
- Corrected oversized single-sample practice previews and exposed suggested/accepted covers as accessible buttons. Verified suggestion activation, cover removal and manual drawing through the final interface.

Screenshots and compact test summaries are in `.build/gallery-feature-evidence/`: `iphone-export-review.png`, `ipad-library.png`, `ipad-batch-review.png`, `ipad-trimmed-export.png`, `ipad-duress-practice.png`, `iphone-tests.json` and `ipad-tests.json`. Full test result bundles are named above. Only generated sample content was used.

## Limits

Storage tests use synthetic bytes for RAW and paired resources, not a physical camera's RAW/Live Photo acquisition. A hardware-device check of PhotoKit resource combinations and Vision performance remains separate from simulator verification. Face suggestions can miss subjects; video covers do not track motion. These changes do not alter the security-key ceremony or demonstrate a new physical-key test. No App Store upload, release, commit or push is part of this validation.
