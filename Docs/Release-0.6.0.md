# Noct Gallery 0.6.0 — build 14

Implemented October 17, 2026. The app, import extension and test configurations use **0.6.0 (14)**. This is a local implementation and validation record; no 0.6.0 upload or review submission has been made.

## Changes

- Gallery taps open fullscreen with a neighboring filmstrip, favorite, edit, share, information and deletion controls. Grid density and date grouping are protected preferences. iPad has an album/tools sidebar; accessibility text sizes reduce grid columns.
- Files and incoming-share imports continue after individual failures, report each result and retry only failures/cancelled sources. Cancellation stops pending work. Source files stay intact; failed incoming files remain encrypted. Retry handles clear on lock.
- Search ranks matches and explains their source. English date/type/album scopes use actual stored metadata, including “photos coffee last month”, “type:video bicycle in 2025” and “album:Weekend”. Optional AI receives only the remaining subject. A transient incremental index and bounded thumbnail cache reduce repeated work; locking clears them.
- Photo editing adds crop corner handles, aspect ratios, precise non-drag controls, undo/redo, original comparison, and brightness/contrast/saturation. Saved recipes stay encrypted and preserve original bytes.
- Video editing adds a twelve-frame filmstrip, frame stepping, trim markers, selected blur keyframe navigation/removal, a transient waveform and muted-section bands. Times refer to the original clip. Encoded output remains the final review.
- Recently Deleted is an encrypted opt-in, off by default, retaining ordinary deletions for seven days. Identify retained media by its encrypted thumbnail, then restore or permanently remove items. Expiry runs on unlock/foreground refresh while unlocked. Duress/reset bypass retention; a previously selected deleted decoy cannot survive.
- Video output defaults to 1080p/30 fps and offers smaller exports or up to 4K/60 fps, capped by source and device capability. Output uses SDR Rec.709; HDR is not preserved. Higher quality retains the same blur, audio, metadata and timestamp checks. Standard batches are capped at 512 MB, high-quality batches at 1 GB.

The interface remains English. Smart Albums, backups, device transfer and Noctweave sharing remain excluded. Tagging, AI phrase interpretation and text indexing remain off by default. Unsupported Apple Intelligence devices hide Smart Search; supported but unavailable devices show disabled controls.

## Validation

The native iOS-on-Mac functional suite passed **121 tests, no failures or skips**, including actual Vision classification, local AI phrase interpretation, legacy decoding, encrypted recovery, seven-day expiry, duress, corrupt-index rejection, per-file failures/retry/cancellation, 4K/60 fps encoding, audio muting and transient timeline generation. Subsequent browsing/cache/video fixes have focused checks recorded below.

Native rendered review uses fictional photographic media and covers the library, explicit search scopes, fullscreen viewer, crop/color editor, timeline, video quality, import summary, recovery and large text. Screenshots are captures of SwiftUI/UIKit views; filenames and import errors in the report layout fixture are illustrative. Functional import results are separately tested against real temporary files. Generated media belongs only to disposable tests, not the shipping app.

The full iPhone 17 Simulator run passed 120 tests with one explicit unavailable-language-model skip. The first iPad run passed 120 tests and skipped that model test, but its added fractional-video test exposed the timestamp rounding defect. That failure was retained and corrected; all nine native video tests then passed. Final device regressions and the separate capture rerun cover the corrected implementation.

Rendered inspection confirmed phone/tablet grid layouts, month ordering, the iPad sidebar, fullscreen filmstrip/actions, crop handles and capped preview size, color controls, search scopes/reasons, timeline markers, video presets, import summary and large text. The recovery list was then given higher-contrast text and session-gated encrypted thumbnails. Pointer-driven navigation remains unverified: the computer-use tool could not launch the standalone review app or Simulator UI. Model lifecycle tests and native rendered views are separate evidence, not a claim of manual end-to-end testing.

### Final checks

| Check | Result |
| --- | --- |
| Native functional suite | 121 passed, no failures or skips; real classification and local AI interpretation included |
| Final iPhone regressions | 18 passed, no failures or skips; recovery, search, encoded video and eleven rendered screens |
| Final iPad regressions | 17 functional checks passed; interrupted render was rerun separately and passed with eleven captures |
| Native viewer/recovery checks | 6 passed, including refreshing an already-open zoom view after editing |
| Native encoded-video checks | 9 passed, including actual 4K/60 fps and 23.976 fps output |
| Native final rendering/share lifecycle | 4 passed; eleven current native captures and export cleanup |
| Generic iOS Release build | Passed with signing disabled; app and embedded extension both report 0.6.0 (14) |
| Shipping bundle contents | No test bundle, marketing photographs or headphone fixture |
| Whitespace checks | Passed |

The first unsigned Simulator attempt lacked working Keychain access and was replaced by a normally signed test run. A combined two-destination Xcode run stalled during launch and was stopped; separate-device runs above provide the final evidence. These infrastructure failures and the corrected organization-cache/fractional-video regressions are retained in private logs. They are not counted as successful tests. Existing SDK/YubiKit deprecation and Simulator media/QoS warnings remain in the logs.

### Large-library measurement

The native Debug benchmark compares three identical production matcher queries and asserts identical item sets. In the final native functional run, at 1,000 items the original path took 71 ms and the compiled index 5 ms after a 22 ms build. At 10,000 items, the original path took 790 ms and the compiled index 63 ms after a 227 ms build. These are single-run local measurements, not physical iPhone performance guarantees. Index construction is separate from per-query work. The organization record remains bounded to 4 MiB.

### Reproduction

Use the existing destination IDs from Xcode; do not create or erase simulators. Native functional tests use the isolated bundle:

~~~sh
rtk proxy xcodebuild -project NoctGallery.xcodeproj -scheme NoctGallery \
  -destination 'platform=macOS,id=<existing-native-id>' \
  -derivedDataPath .build/gallery-next -parallel-testing-enabled NO \
  GALLERY_APP_BUNDLE_IDENTIFIER=com.luizwidmer.NoctGallery.gallery-features.visual-review \
  GALLERY_DISPLAY_NAME='Gallery Feature Review' \
  -skip-testing:NoctGalleryTests/GalleryVisualFixtureTests test
~~~

Photographic render tests require the private marketing sample pack in the test bundle and an isolated identifier ending in .gallery-features.visual-review. The installer and renderer remove/recreate only the disposable app's vault and credentials, never Photos or production app data. Remove the temporary sample pack after review.

The iOS 26.5 Simulator cannot run the real image classifier reliably. Three classifier-dependent tests are explicitly excluded there as documented in [the earlier validation](Validation-2026-10-09-SmartSearch.md); the real language-model test skips when unavailable. Those checks run against genuine models in the native suite. Controlled availability providers are used only for state/layout tests.

Physical iPhone/iPad camera, Face ID, USB key, encoder performance and HDR-source appearance remain unverified by these local runs. A successful unsigned device build does not establish distribution signing, App Store upload, approval or availability.

## Privacy and release preparation

[README](../README.md), [security model](../SECURITY.md) and [media guide](MediaMetadata.md) describe the new behavior and limits. [The updated privacy policy](PrivacyPolicy-2026-10-17.md) is a draft for the next release and has not replaced the published October 9 policy. No permissions, cloud model or collection endpoint were added.

Private build logs, test results, native captures and benchmark attachments are retained outside this repository at PICCP Project/ReleaseArtifacts/NoctGallery-0.6.0-2026-10-17/.
