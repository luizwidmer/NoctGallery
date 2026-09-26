<p align="center">
  <img src="NoctGallery/BrandAssets/NoctGalleryAppIcon.svg" alt="Noct Gallery icon" width="112">
</p>

<a id="noct-gallery"></a>

<h1 align="center">Noct Gallery</h1>

<p align="center"><strong>Private photos and videos. Deliberate control over what you share.</strong></p>

<p align="center">
  <a href="#overview">Overview</a> ·
  <a href="#quick-start">Quick start</a> ·
  <a href="#features">Features</a> ·
  <a href="#security-and-privacy">Security</a> ·
  <a href="#documentation">Documentation</a>
</p>

## Overview

Noct Gallery combines an encrypted private library, an in-app camera, and
media export tools for iPhone and iPad. Keep originals in Apple Photos,
work with private copies, and choose which metadata travels with a share.

| Detail | At a glance |
| --- | --- |
| Platform | iPhone · iPad |
| Built with | SwiftUI · PhotoKit · AVFoundation |
| License | [AGPL-3.0-or-later](LICENSE) |

<a id="build"></a>

## Quick start

Run commands from this repository.

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

Tests use isolated temporary storage and in-memory credential stores. A Simulator build does not validate a physical camera, Face ID hardware or a connected USB key. The local FIDO2 flow needs no associated-domain or NFC entitlement. A separate review installation can be built by overriding `PRODUCT_BUNDLE_IDENTIFIER` and `GALLERY_DISPLAY_NAME`.

## Features

| Workflow | What you can do |
| --- | --- |
| Private library | Browse Photos, copy cleaned media, or move supported originals into encrypted storage. |
| Private camera | Capture directly into Gallery, without saving to Apple Photos. |
| Deliberate sharing | Cover sensitive details, trim or mute videos, then inspect the actual export and its metadata before sharing. |
| Organization | Encrypted albums, favorites and tags, with batch sharing, organization, copy and deletion. |
| Metadata editing | Save presets and choose optional coordinates by map, search, or numeric input. |
| App protection | Require a PIN, biometrics, a compatible physically connected USB FIDO2 key, or every selected factor. |
| Duress actions | Reset local storage or retain selected items under a newly rotated key; rehearse with isolated sample media. |

### Move or copy

**Move to Private Gallery** preserves the original file bytes and embedded metadata, verifies the encrypted copy, then asks Photos to delete its original. If saving, verification or deletion fails, the Photos original stays. Cancelling deletion keeps the encrypted copy; the same screen offers **Remove Photos Original** to retry without importing another copy.

Moves support JPEG, PNG, HEIC/HEIF, MOV, MP4, M4V, system-recognized RAW images, RAW/photo pairs and Live Photos, up to 1 GB across all components. Every component is encrypted and compared with its original before Photos deletion. Live Photo motion plays from the private detail screen. RAW/photo pairs use the rendered companion for ordinary viewing. Edited assets and unknown resource combinations remain in Photos rather than silently losing a component. **Copy to Private Gallery** keeps the Photos source and uses a cleaned/re-encoded import.

Photos deletion can sync through iCloud Photos and leaves the item in Recently Deleted for up to 30 days. Clear that album in Photos for immediate permanent removal. Gallery does not promise to erase external copies or backups.

### Export profiles

Still images are rebuilt from pixels. Video and audio are re-encoded as
H.264/AAC MOV, up to 1080p at 30 fps; video inputs are limited to 4K,
10 minutes, and 1 GB. Apple Photos originals remain unchanged.

Metadata presets include 21 camera models across eight manufacturers and
40 camera/lens combinations. Use compatible randomized or manual exposure,
vary dates and time zones, add an optional GPS area, omit camera identity, or
strip optional metadata entirely. Maps uses an explicit place search; Gallery
does not request your current location.

**Prepare to Share** lets you draw opaque covers, optionally use on-device face/text suggestions, and choose saved metadata presets. Video covers stay at fixed positions throughout the selected clip; trim and audio removal are optional. Suggestions can miss faces, text or plates and must be reviewed. The next screen plays or displays the encoded output, shows its size and metadata, and compares removed/changed fields. Batch sharing handles up to 20 copies, with a 512 MB combined export limit. Each item needs its own review for sensitive visible content.

Albums, tags and favorites are encrypted in the vault and available only while unlocked. Search includes album names and tags, without a system search index or stored OCR transcripts. Batch organization and deletion accept up to 500 selected items. Deleting an album keeps its media.

### App protection

Ordinary authentication runs Key → Biometrics → PIN, requiring every selected
factor. Backgrounding or manually locking the app discards active private
media keys and playback files.

An optional PIN-only waiting screen hides biometric and key hints. Hold the
Gallery logo for six seconds to start ordinary checks; the visible field still
accepts duress PINs. In this mode, no biometric prompt starts automatically.

Connect a FIDO2 key by USB. Gallery creates and verifies challenges on-device using a short-lived `localhost` page in Apple's ephemeral authentication browser. No account, hosted authentication service, associated website, or internet connection is required. The browser handles key PIN and touch prompts and supports standard USB FIDO2 independently of the older SDK's FIDO-over-CCID requirement. Keys must support ES256 and user verification. Registration includes a fresh assertion before a credential can be saved.

Gallery's NFC scanner and permissions are removed. Apple's own security-key sheet controls its connection options and may offer NFC on capable devices. Existing registrations keep their original `noctgallery-app-lock.invalid` scope and USB smart-card path, which requires compatible FIDO over CCID (YubiKey 5.8+). Re-register after unlocking to use the new local flow; credentials are never silently migrated or bypassed. See [local FIDO2 design](Docs/LocalFIDO2.md).

When a duress action retains selected items, Gallery re-encrypts them with a
new storage key and makes the duress PIN the sole ordinary unlock PIN.
Interrupted actions resume before unlocking.

Duress practice is implemented but temporarily hidden from the app. Its isolated sample vault and tests remain available in the code; there are no navigation entry points.

<a id="important-boundaries"></a>

## Security and privacy

The private gallery is on-device storage, excluded from backup. Gallery has no sync, account or key recovery service. Forgotten required credentials require a destructive reset. Biometric checks use the device's enrolled biometrics without a passcode fallback; protect the device passcode and enrollment settings.

A private camera still uses Apple's camera hardware, permission system and capture indicators. It bypasses the Photos save workflow, not iOS security. A clean conversion changes encoding and may reduce resolution, frame rate, dynamic range and audio channels; it is not an archival copy of the original. Shared copies of Live Photos/RAW items are rendered stills; their original components remain in the vault. RAW editing, depth, spatial video, subtitles and additional audio tracks are not preserved in clean exports.

PhotoKit may download iCloud-backed media. Maps and place search contact Apple. StoreKit handles optional tips and review prompts. Gallery has no developer-operated upload service, analytics or advertising. Sharing gives the selected destination a decrypted file. Temporary media is protected, excluded from backup, and cleared after use, on lock and at launch.

Decoy metadata is optional synthetic data based on documented equipment. It is not a camera's authentic signature or evidence of origin. Pixels, sound, recognizable scenes, generated-value patterns and external copies can still identify media. Duress actions only affect Gallery's storage; they cannot revoke shared copies or erase Apple Photos originals. Read [SECURITY.md](SECURITY.md) for the full boundary.

## Documentation

| Read | For |
| --- | --- |
| [Metadata and format guide](Docs/MediaMetadata.md) | Formats, presets, and conversion tradeoffs |
| [Security model](SECURITY.md) | Storage, authentication, and reporting |
| [Verification record](Docs/Validation-2026-09-17.md) | Recorded tests and physical-device limits |
| [0.2.0 release notes](Docs/Release-0.2.0.md) | Build evidence and release preparation |
| [Privacy policy draft](Docs/PrivacyPolicy-2026-09-19.md) | Prepared text and publication status |

<a id="contributing-and-security"></a>

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before proposing changes. Report
vulnerabilities privately using [SECURITY.md](SECURITY.md).

## License

Copyright (C) 2026 Luiz Widmer. Noct Gallery is free software licensed under
the [GNU Affero General Public License v3.0 or later](LICENSE).
