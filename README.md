# Noct Gallery

[![License: AGPL v3 or later](https://img.shields.io/badge/license-AGPL--3.0--or--later-6757d9.svg)](LICENSE)

Noct Gallery is a private photo and video gallery for iPhone and iPad, with a built-in camera and tools for sharing newly encoded media with clean or chosen metadata.

## Features

- Browse selected Apple Photos or an independent encrypted private gallery.
- Capture photos and videos directly into private storage using AVFoundation. Gallery does not save captures to Apple Photos or call its built-in camera app.
- Play videos, import private copies, edit saved metadata, and share clean or decoy copies. Apple Photos originals remain unchanged.
- Rebuild still images from pixels; rebuild video and audio as H.264/AAC MOV, up to 1080p at 30 fps. Input videos are limited to 4K, 10 minutes and 1 GB.
- Choose 21 camera models across eight manufacturers and 40 camera/lens combinations, with compatible randomized exposure or manual settings. Save presets, vary dates/time zones and optional GPS areas, omit camera identity while changing dates, or strip optional metadata entirely.
- Set GPS coordinates with a map pin, an explicit Apple Maps place search, or numeric coordinates. The app does not request current location.
- Protect the entire app with a six-digit PIN, Face ID/Touch ID, an NFC FIDO2 security key on compatible iPhones, or combinations requiring every selected method. Ordinary authentication runs Key → Biometrics → PIN. Backgrounding and manual locking discard private media keys and playback files from the active session.
- Optionally show only a PIN lock screen, even with biometric/key unlock. Hold the Gallery logo for two seconds to start ordinary checks; the visible field accepts duress PINs. No automatic biometric prompt or visible key/biometric hint appears in this mode.
- Configure duress PINs to reset Gallery or retain only selected private photos and videos. Retained items are re-encrypted with a new storage key; the duress PIN becomes the sole ordinary unlock PIN. Interrupted actions resume before unlocking.

See [the metadata research and format boundary](Docs/MediaMetadata.md), [security model](SECURITY.md), and [verification record](Docs/Validation-2026-09-17.md).

## Build

Requirements: Xcode 26.6, iOS 26 SDK, and the Noctweave public security-key package. The Xcode project references `../PICCP Project/NoctweaveSecurityKeys`, including its pinned YubiKit sources. Place that checkout beside NoctGallery or update the local package reference in Xcode. No proprietary messaging-client or relay-app source is used.

```sh
xcodebuild -project NoctGallery.xcodeproj -scheme NoctGallery \
  -destination 'generic/platform=iOS Simulator' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES EXCLUDED_ARCHS=x86_64 build

xcodebuild -project NoctGallery.xcodeproj -scheme NoctGallery \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES EXCLUDED_ARCHS=x86_64 test
```

Tests use isolated temporary storage and in-memory credential stores. A Simulator build does not validate a physical camera, Face ID hardware or NFC key. Device builds require the NFC Tag Reading capability and a matching provisioning profile. A separate review installation can be built by overriding `PRODUCT_BUNDLE_IDENTIFIER` and `GALLERY_DISPLAY_NAME`.

## Important boundaries

The private gallery is on-device storage, excluded from backup. Gallery has no sync, account or key recovery service. Forgotten required credentials require a destructive reset. Biometric checks use the device's enrolled biometrics without a passcode fallback; protect the device passcode and enrollment settings.

A private camera still uses Apple's camera hardware, permission system and capture indicators. It bypasses the Photos save workflow, not iOS security. A clean conversion changes encoding and may reduce resolution, frame rate, dynamic range and audio channels; it is not an archival copy of the original. Live Photo paired motion, RAW editing, depth, spatial video, subtitles and additional audio tracks are not preserved.

PhotoKit may download iCloud-backed media. Maps and place search contact Apple. StoreKit handles optional tips and review prompts. Gallery has no developer-operated upload service, analytics or advertising. Sharing gives the selected destination a decrypted file. Temporary media is protected, excluded from backup, and cleared after use, on lock and at launch.

Decoy metadata is optional synthetic data based on documented equipment. It is not a camera's authentic signature or evidence of origin. Pixels, sound, recognizable scenes, generated-value patterns and external copies can still identify media. Duress actions only affect Gallery's storage; they cannot revoke shared copies or erase Apple Photos originals. Read [SECURITY.md](SECURITY.md) for the full boundary.

## Contributing and security

Read [CONTRIBUTING.md](CONTRIBUTING.md) before proposing changes. Report
vulnerabilities privately using [SECURITY.md](SECURITY.md).

## License

Copyright (C) 2026 Luiz Widmer. Noct Gallery is free software licensed under
the [GNU Affero General Public License v3.0 or later](LICENSE).
