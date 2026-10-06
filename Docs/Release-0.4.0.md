# Noct Gallery 0.4.0 (12)

Submitted October 6, 2026 at 11:15 AM (America/Bahia).
App: `6810294404`. Bundle: `com.luizwidmer.NoctGallery`.

**App Store Connect status: Waiting for Review.** Submission:
`3fc8441f-665f-4c53-97df-645d157a4348`, containing **0.4.0 (12)**.
Apple approval and public availability of this version are pending.

## Changes

- Fullscreen viewing, sorting and filters; encrypted captions and private notes.
- Storage details, manual duplicate review and optional encrypted on-device text search.
- Reversible photo crop, rotation and straightening; improved cover editing and complete sharing presets.
- Moving video covers with local tracking or manual keyframes, plus selected audio muting.
- Private camera focus, exposure, zoom, grid, flash and timer controls where supported.
- Files import and a share extension with an encrypted, bounded incoming queue.

Smart Albums, backups, device transfer and Noctweave sharing are excluded.

## Release preparation

The application and embedded import extension both use version **0.4.0**, build
**12**. Their signed archive, matching App Group entitlements, embedded profiles
and dSYMs were verified. Upload succeeded, and App Store Connect finished
processing build 12. It is attached to the submitted 0.4.0 version.

The listing description, promotional text, keywords, release notes and review
instructions are updated. Existing review contacts and automatic release after
approval are retained. The October 6 privacy policy is published and its public
page was read back to verify encrypted imports, private notes, reversible editing,
optional OCR retention and local tracking. See
[the policy source](PrivacyPolicy-2026-10-06.md).

Screenshots use native app views with generated fictional travel/lifestyle photos
and a fictional hotel itinerary. These media files are screenshot resources, not
preloaded customer content. Original generated media, prompts and exact rendered
screenshots are retained in the private release evidence directory.
Eight iPhone screenshots (1320 × 2868) and seven iPad screenshots (2064 × 2752)
were uploaded and accepted. The iPad sequence starts with the photo editor.
The screenshot tests passed on both iPhone 17 and iPad Pro 13-inch (M5);
the visible cells were allowed to finish loading before the final captures.

For reproduction, copy the five retained `sample-media/marketing-*.jpg` files into
the ignored `NoctGalleryTests/MarketingMedia/` folder and run the disposable
fixture tests. The helper uses real app rendering and export code. Remove that
temporary resource folder afterward. These media files are absent from the
production archive. `compose-final.mjs` and `screenshot-manifest-final.json`
record the final compositions, source captures and hashes; earlier compositions
in the evidence directory were superseded and were not submitted.

## Validation and evidence

See [library tools validation](Validation-2026-10-06-LibraryTools.md) for 84-test
iPhone and iPad runs, focused inbox checks and physical-hardware limits. Release
signing is verified separately from device execution. The screenshot helper runs
only in the disposable visual-review app and removes its keys/media after capture.

Private evidence lives in the parent workspace at
`ReleaseArtifacts/NoctGallery-0.4.0-2026-10-06/`: archive, dSYMs, signing validation,
upload logs, listing metadata, privacy-policy HTML, generated media/prompts,
screenshots and test results. This directory is not part of the public repository.

The review detail page was read after submission and showed **Waiting for Review**
for **0.4.0 (12)**. The retained `RELEASE-STATUS.md` and
`evidence/submitted-release-ax.txt` / `evidence/submitted-release.png` record that
state. Automatic release after approval and immediate availability to all users
remain selected. At submission time, these changes had not yet been committed
or pushed.
