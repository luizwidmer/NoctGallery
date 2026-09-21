# Noct Gallery 0.2.0 (7)

Prepared September 19, 2026.

## Build and validation

- Marketing version 0.2.0; build 7; production bundle `com.luizwidmer.NoctGallery`.
- Refreshed the vector app icon and generated an opaque 1024-pixel App Store icon. The same artwork is used for the in-app brand mark.
- Info.plist and Settings now read the configured version instead of a hard-coded value.
- Xcode Simulator tests: **42 passed, zero failures**.
- Signed Release archive succeeded. Strict code-signature verification passed. The app and dSYM share arm64 UUID `82298E7D-2CCD-3286-949D-7D167C482F30`.
- App Store Connect upload succeeded. Apple processed build 7 and it is attached to the 0.2.0 draft. App Store Connect accepted Add for Review and marked the version **Ready for Review**. The final Submit for Review action has not been performed.

## Store presentation

Prepared and uploaded five iPhone 6.9-inch screenshots (1320 × 2868) and four iPad 13-inch screenshots (2064 × 2752). Each contains an actual app capture with a consistent headline and device frame. Screens cover private photos, video, metadata editing, coordinate selection, and iPhone PIN protection.

All imagery uses disposable demonstration media. The photo sources were generated for the earlier release; short demonstration videos were derived from those images. No personal media was used. iPhone and iPad compositions were inspected visually, and their order was checked in App Store Connect.

The description, promotional text, keywords, subtitle, release notes and reviewer instructions describe the new private gallery and camera features. Manual release is retained. Uploading a build is distinct from App Review approval or public release.

## Evidence

The production archive, test result bundle, logs, source captures, composed screenshots, artwork, metadata, privacy-policy draft and reproducible screenshot composition script are retained in the private parent workspace at:

`ReleaseArtifacts/NoctGallery-0.2.0-2026-09-19/`

Task-specific DerivedData was removed after preserving the archive and test evidence. Existing simulators were reused and shut down after capture.

## Limits

This release run does not resolve the previously reported physical NFC-key failure. It adds no claim of universal hardware-key compatibility. Physical-device findings and remaining camera/key validation limits are recorded in `Validation-2026-09-17.md`.

The updated privacy policy is prepared locally. Safari’s WordPress UI exposes only the account menu to the controller and provides no screenshot, including on the page editor. The existing policy page is ID 97. The prepared text is in `PrivacyPolicy-2026-09-19.md`; it has not replaced the public policy. Publish it before submitting the draft to App Review.
