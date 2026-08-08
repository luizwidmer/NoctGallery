# Noct Gallery

[![License: AGPL v3 or later](https://img.shields.io/badge/license-AGPL--3.0--or--later-6757d9.svg)](LICENSE)

Noct Gallery is a privacy-first viewer and sharing layer for the existing iPhone and iPad photo library. It does not import media into a second vault or retain private copies. Images are read from PhotoKit and processed only when the user shares them.

## What works

- Browse the system photo library through PhotoKit, including limited-library mode.
- Search by date and inspect an image without copying its original bytes into app storage.
- Share through a bounded decode, orientation normalization, and clean re-encode pipeline.
- Strip EXIF, GPS, TIFF, IPTC, XMP, filenames, and opaque ancillary payloads from the shared copy.
- Create an explicit shared copy with newly generated decoy EXIF/TIFF/GPS metadata.
- Randomize temporary export filenames and remove them when sharing completes or is cancelled.
- Reject oversized, malformed, empty, and unsupported source images.

## Build

Requirements: Xcode 26.6 or newer and the iOS 26 SDK.

```sh
xcodebuild \
  -project NoctGallery.xcodeproj \
  -scheme NoctGallery \
  -destination 'generic/platform=iOS Simulator' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES EXCLUDED_ARCHS=x86_64 \
  CODE_SIGNING_ALLOWED=NO build
```

Run tests with an installed ARM64 iPhone simulator:

```sh
xcodebuild \
  -project NoctGallery.xcodeproj \
  -scheme NoctGallery \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES EXCLUDED_ARCHS=x86_64 \
  CODE_SIGNING_ALLOWED=NO test
```

## Important boundaries

iOS does not expose Photos as a replaceable default-app category. Noct Gallery can replace the user’s gallery workflow, but it cannot become the operating system’s Photos app. The original remains in the system library and is never modified by Noct Gallery.

PhotoKit may download an iCloud-backed original when the user shares it. A sanitized export must briefly exist as a randomized temporary file because the iOS share sheet consumes a file URL; Noct Gallery deletes that file on completion or cancellation and also purges stale exports at launch. Decoy metadata is optional and does not guarantee anonymity: image content, upload timing, account data, and generated-value patterns may still identify someone. See `SECURITY.md` for the complete threat boundary.

## Contributing and security

Read [CONTRIBUTING.md](CONTRIBUTING.md) before proposing changes. Report
vulnerabilities privately using [SECURITY.md](SECURITY.md).

## License

Copyright (C) 2026 Luiz Widmer. Noct Gallery is free software licensed under
the [GNU Affero General Public License v3.0 or later](LICENSE).
