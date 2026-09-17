# Noct Gallery validation — 2026-09-17

This record covers the private media/video/camera, metadata editor and app protection changes in this working tree. It is not an ecosystem-wide security audit, App Store release approval or a claim of universal hardware-key compatibility.

## Executed automated checks

- Xcode 26.6, iPhone 17 Simulator on iOS 26.5, arm64, parallel testing disabled: **42 tests passed, zero failures** (`tests-final.log`).
- Cases include 3 duress transaction tests, 8 app-lock tests, 4 image sanitizer tests, 10 metadata tests, 5 private storage tests, 7 temporary export tests and 5 video tests.
- The public NoctweaveSecurityKeys package: **12 tests passed**, including strict credential/signature behavior (`security-key-tests.log`).
- Final Simulator app build: **succeeded** (`build-simulator-final.log`). Final signed iPhone Review build: **succeeded**, installed and launched on the connected iPhone 13 (`build-device-final.log`).
- Final changes after the 42-test run were labels and catalog row styling; both app targets were rebuilt afterward.

Metadata tests cover 2,000 seeded profiles across every catalog model/lens and more than 500 distinct exposure combinations; coordinate radius/dateline behavior; no-GPS defaults; date/light consistency; incompatible exposure rejection; legacy preset decoding; and omission of camera tags in date-only mode. An initial test caught two outdoor timestamps falling outside the selected daylight hours. Calendar-based local-time generation and previous-day handling fixed it; the repeated run passed.

Storage tests cover encrypted photo/video round trips, ciphertext modification/reordering, missing-key failure, session invalidation and reset recovery. Duress tests cover retaining selected items under a new key, erasing non-retained items, old-key rejection, interrupted key replacement, committed-action replay, ordinary-unlock blocking, and replacing old factors with the duress PIN. PIN tests cover independent salts, persisted throttling, factor order and early-PIN bypass rejection. Video tests cover H.264/AAC output, optional audio removal, rotation, cancellation, metadata and QuickTime header timestamps.

## Rendered and interactive checks

Using only disposable color-bar images and a three-second generated video:

- iPhone Simulator: private gallery, full image preview, Photos import, video playback/import, metadata editor, map search and selecting Lisbon, private-copy success feedback, camera catalog search/selection, and date-only editor inspected.
- iPad Pro 13-inch (M5) Simulator: private empty state, settings, random metadata options, GPS area/radius controls, and metadata sheets inspected in portrait and landscape. Controls fit and remained scrollable. The temporary iPad run was shut down afterward.
- Discreet mode: configured a disposable duress PIN with ordinary biometric-only authentication and enabled the PIN-front screen. The rendered screen and accessibility tree exposed no biometric/key button or gesture hint; no automatic biometric prompt appeared while idle.
- Entering the disposable duress PIN directly from that biometric-only lock returned to Finish Onboarding and left the private gallery empty. Original Photos fixtures were outside the private reset scope. The unit tests separately verify replacement-PIN persistence and rejection of previous credentials.
- The native UI controller has no long-press-duration API. The two-second logo gesture is implemented but its physical end-to-end confirmation is pending the user's test on the updated iPhone build.

A real Photos video-open check found a dispatch-queue assertion caused by actor-inherited PhotoKit callbacks. Explicit `@Sendable` callbacks fixed it. Opening/importing the same video then succeeded. This was a runtime finding, not inferred from a passing build.

## Physical-device feedback

The user tested the separate **Gallery Review** installation on an iPhone 13 and reported that private photo capture, short video with sound, playback, background locking and not saving to Apple Photos work. They also reported that biometrics and duress retention/PIN replacement work.

The user reported that NFC security-key use did not work, while plugging a key into another iPhone worked. It is not yet established which app/transport path succeeded on that other device, or whether the NFC failure occurred before scanner presentation, tag detection or verification. Questions are pending. **NFC authentication has not been verified successful.** The signed Review app passed `codesign --verify --deep --strict`; both its signature and provisioning profile contain NFC TAG authorization. That rules out a missing TAG entitlement in this build but does not prove an NFC transaction works. The review does not treat the Simulator, a signed entitlement or a successful build as physical key evidence. The updated PIN-front gesture test is also pending physical confirmation.

Gallery currently exposes the documented NFC FIDO path on compatible iPhones. iOS USB smart-card access is not a substitute for generic FIDO HID support; the Yubico iOS SDK documentation explicitly distinguishes these interfaces. There is no continuous-presence claim for NFC. Do not ship generic USB-key marketing based solely on another app's successful system authentication.

## Evidence and remaining limits

Local logs, screenshots and test result bundles are retained under the private workspace runtime folder `PICCP Project/.runtime/gallery-media-2026-09-17`, excluded from source publication. Test result bundles and the signed Review app were preserved; task-specific Simulator/device DerivedData and the package build cache were removed afterward. Both test simulators and Simulator were closed. Test-generated media contained no personal content.

The new private-storage/camera behavior has a privacy-policy draft in this repository. The currently published support-site policy has not been replaced by this turn, and App Store privacy/release metadata has not been updated. No archive upload, TestFlight submission, commit or push is claimed.

No physical iPad, HDR fidelity, all supported input encoders, all key models, power-loss fault injection on real storage, or forensic-erasure guarantee was validated. Existing Apple API deprecation warnings remain for MapKit placemarks and AVFoundation composition APIs; compilation succeeds. See SECURITY.md for compromised-device, external-copy and synthetic-metadata limits.
