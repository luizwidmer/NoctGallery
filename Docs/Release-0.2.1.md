# Noct Gallery 0.2.1 (10)

Prepared September 22, 2026. Bundle: `com.luizwidmer.NoctGallery`.

## Changes

- Move supported originals into encrypted private storage without re-encoding or changing embedded metadata. Verify the complete encrypted copy before requesting Photos deletion.
- Preserve both copies if Photos deletion is rejected; retry from the same screen without importing another copy.
- Keep unsupported and multipart originals in Photos. Document Recently Deleted retention and iCloud Photos deletion behavior.
- Repair Leave a Review with the app's assigned App Store ID.
- Explain the six-second logo hold in protection settings and match the actual discreet-unlock gesture.
- Shorten onboarding, settings, metadata, sharing and duress copy.

## Validation

All 46 Gallery tests passed, including save failure, corruption, cancellation, lock and deletion-retry cases. Simulator PhotoKit photo/video moves and private playback passed. The moved MP4 matched the original bytes and metadata. Real testing caught and fixed a PhotoKit callback actor-isolation crash before release.

The review URL resolves to the correct App Store listing. The physical-device review composer was not tested. Existing hardware-key code is unchanged.

## Release evidence

The private parent workspace keeps build, signing, upload and App Store submission evidence under `ReleaseArtifacts/NoctGallery-0.2.1-2026-09-22/`. Functional tests and Simulator screenshots are under `ReleaseArtifacts/NoctGallery-fixes-2026-09-22/`. Submission and approval status must be read from current App Store Connect evidence.
