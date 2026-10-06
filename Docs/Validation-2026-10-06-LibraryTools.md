# Library tools verification — October 6, 2026

This records the feature-validation baseline. Subsequent signed archive, App Store
upload, published policy and submission evidence are recorded separately in
[the 0.4.0 release record](Release-0.4.0.md).

This change implements the requested local gallery features. Smart Albums,
backup/restore, device transfer and Noctweave sharing are excluded. It keeps the
existing encrypted vault and public security-key dependency; it adds no relay,
account, cloud index or synchronization authority.

## Implemented scope

| Feature | Behavior |
| --- | --- |
| Fullscreen viewer | Pinch/double-tap photo zoom, swipe/arrow navigation and video playback. |
| Sort and filter | Capture/import date, original size and duration ordering; date range, media, format, tag and minimum video duration filters. |
| Captions and notes | Encrypted item descriptions, searchable while unlocked and excluded from exports. |
| Storage dashboard | Original/encrypted item sizes, overlapping album totals, largest items and temporary file cleanup. |
| Reversible photo editing | Encrypted crop, quarter-turn rotation and straightening recipes; original resources remain unchanged. |
| Cover editor | Draw, move, resize, delete, zoom, pan and undo/redo. |
| Sharing presets | Photo format/size/quality, video size, full audio removal and optional metadata; three built-ins and bounded custom presets. |
| Camera controls | Tap focus/metering, bounded zoom/exposure, grid, flash and timer with cancellation. |
| Files and share-sheet import | Preserved original resources, authenticated verification and a bounded encrypted incoming queue. |
| Duplicate review | Authenticated original-byte hashes and temporary local similarity suggestions, with manual deletion. |
| Private text search | Opt-in on-device OCR saved only in the encrypted vault; disabling removes transcripts. |
| Moving video covers | On-device tracking in both directions from a reference frame and editable manual keyframes. |
| Selective audio muting | Source-time intervals silence decoded PCM before AAC encoding; other audio is retained. |

## Executed checks

Xcode 27.0 (27A266a), arm64; existing iOS 26.5 Simulators were reused.

| Check | Result |
| --- | --- |
| Full iPhone 17 suite | 84 tests passed, zero failures/skips. |
| Full iPad (A16) suite | 84 tests passed, zero failures/skips. |
| Final encrypted-inbox checks | All five tests passed after adding ciphertext-overhead accounting and interrupted staging cleanup. |
| Disposable screenshot/cleanup runs | Both fixture tests passed on each device, including removal of review keys and media. |
| Simulator application/extension build | Passed. |
| Release build for generic iOS, signing disabled | Application and embedded share extension passed. |
| Plists, entitlements and project file | `plutil -lint` passed. |
| Whitespace | `git diff --check` passed. |

Each full suite includes 82 functional tests and two disposable fixture/rendering
tests. Production-bundle runs skip both fixture tests. The complete suites ran
before the final inbox-bound/staging refinement; its affected tests were then
rerun. Only fixture cleanup changed afterward.

Coverage includes released-record decoding; encrypted notes, recipes and OCR
reopening/disable behavior; duress index removal; photo geometry and source
preservation; actual Vision OCR and similarity processing; authenticated duplicate
hashes; file format sniffing; preset bounds; incoming queue encryption, key mismatch,
tampering, truncation, trailing bytes, cancellation, linked paths and storage
bounds; and unlock-gated incoming import and cleanup.

Video checks include actual automatic tracking of a moving textured fixture,
moving covers in a freshly encoded trimmed clip, and decoding the final AAC track
to verify selected silence and preserved audio before/after it. Existing metadata,
original-component, authentication, rekeying, cancellation and export lifecycle
tests also passed.

## Rendered inspection and limits

Eleven native screens per device were rendered through `UIHostingController`,
captured as XCTest attachments and visually inspected: private library, detail,
fullscreen, photo editor, notes, photo/video share preparation, storage, text-search
settings, incoming queue and settings. The fullscreen footer was corrected during
review; its cramped date label and UIKit toolbar hierarchy warning are resolved in
the final captures. This checks the sampled layouts, not every gesture or workflow.

The disposable app uses a separate bundle identifier and App Group. Generated
media contains no personal data, and these tests do not change the Simulator's
Photos library. Test apps and task-specific build products were removed after
compact result summaries and screenshots were saved in ignored `.build/` evidence
folders. Existing Simulators and prior evidence were preserved.

Physical focus/exposure/flash/capture, Face ID and USB-key hardware were not tested.
Share-extension handoff from another application and App Group provisioning on a
physical device remain unverified. The unsigned device build does not prove signing
or installation. Provision both app and extension with
`group.<GALLERY_APP_BUNDLE_IDENTIFIER>` before device installation.

Tracking, OCR and similarity can miss content. Tracking rejects low-confidence
results, but interpolation between sampled frames can still expose movement;
review the complete encoded clip. Analysis is bounded to the documented batches,
and the encrypted organization index retains its 4 MiB limit.

A cleanup-only iPhone launch initially failed with Simulator preflight status
`Busy`. A normal boot and retry passed both tests; no Simulator was erased or
recreated.

Builds retain existing Apple API/YubiKit deprecation and concurrency warnings, plus
the harmless AppIntents extraction notice. One full iPhone test run reported an
AVFoundation priority-inversion warning while composing the audio fixture; it did
not fail the test. No release archive, App Store submission, protocol compatibility
certification, privacy-policy publication or complete security/UI audit is claimed.

## Reproduction

Use the commands in [README.md](../README.md) for ordinary builds and tests. For
disposable fixture rendering, add these build settings and select the fixture class:

```sh
xcodebuild -project NoctGallery.xcodeproj -scheme NoctGallery \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  -only-testing:NoctGalleryTests/GalleryVisualFixtureTests \
  GALLERY_APP_BUNDLE_IDENTIFIER=com.luizwidmer.NoctGallery.gallery-features.visual-review \
  GALLERY_DISPLAY_NAME='Gallery Review' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES EXCLUDED_ARCHS=x86_64 test
```

Remove `-only-testing` to run the full suite with the disposable review app. Use
`name=iPad (A16)` for the other validated device. Fixture tests deliberately reset
that separate review app; never use the review bundle for personal media.
