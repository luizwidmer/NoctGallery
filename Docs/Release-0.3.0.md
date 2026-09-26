# Noct Gallery 0.3.0 (11)

Prepared September 26, 2026. Bundle: `com.luizwidmer.NoctGallery`.

## Changes

- Preview the actual exported file and inspect remaining, removed and changed metadata before sharing.
- Burn opaque covers into shared copies, with on-device face/text suggestions and manual placement. Trim videos and remove audio; video covers are static and require full-clip review.
- Organize private media with encrypted albums, favorites and tags. Search organization metadata and use batch actions and saved sharing presets.
- Preserve supported Live Photo and RAW components in encrypted private storage. Verify every component before requesting Photos deletion; unsupported or edited combinations remain in Photos.
- Preserve compatibility with existing single-resource private media and clear organization metadata during duress actions.
- Keep duress practice hidden from both Settings and Duress & Decoys; its isolated implementation and tests remain in the code.

Encrypted backup/device transfer is excluded. Existing hardware-key authentication is unchanged.

## Validation

The feature suite passed 64 tests on iPhone Simulator and 63 tests on iPad Simulator before the additional Vision suggestion test. Actual export previews, permanent covers, native sharing, mixed photo/video batches, organization search and trimming were checked through the rendered interface. Debug Simulator and unsigned Release builds passed. See `Validation-2026-09-26-GalleryFeatures.md` for coverage and device-testing limits.

Physical-device acquisition of RAW/Live Photo resources remains a separate check. Test preservation uses synthetic resource bytes; no universal format compatibility is claimed.

## Release evidence

The private parent workspace retains signing, archive, upload, screenshot and submission evidence under `ReleaseArtifacts/NoctGallery-0.3.0-2026-09-26/`. Read the current evidence or App Store Connect for submission/approval status; preparing this document does not imply either.
