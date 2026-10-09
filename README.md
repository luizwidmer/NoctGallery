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

Tests use isolated temporary storage and in-memory credential stores. A Simulator build does not validate a physical camera, Face ID hardware or a connected USB key. The local FIDO2 flow needs no associated-domain or NFC entitlement. A separate review installation can be built by overriding `GALLERY_APP_BUNDLE_IDENTIFIER` and `GALLERY_DISPLAY_NAME`; the import extension and App Group identifiers follow that bundle identifier. Disposable screen-rendering tests require an identifier ending in `.gallery-features.visual-review` and otherwise skip.

Physical builds must provision the main app and `NoctGalleryImport` extension with their shared App Group, `group.<GALLERY_APP_BUNDLE_IDENTIFIER>`. Open and unlock Gallery once before using its share-sheet import destination. Signing and App Group registration in the Apple developer account are separate from a Simulator or unsigned build.

## Features

| Workflow | What you can do |
| --- | --- |
| Private library | Browse Photos, copy cleaned media, or move supported originals into encrypted storage. |
| Viewing | Open a fullscreen viewer with pinch/double-tap zoom, swipe navigation and video playback. |
| Private camera | Capture directly into Gallery, with tap focus, exposure, zoom, grid, flash and photo timer controls. |
| Deliberate sharing | Move/resize blur areas, undo/redo, zoom, track video blur or add keyframes, trim clips and silence selected audio intervals. Review the encoded copy before sharing. |
| Smart Search | Off by default. On-device object/scene tags, editable synonyms and local AI interpretation on supported Apple Intelligence devices. Tags and synonyms stay encrypted. |
| Organization | Encrypted albums, favorites, tags, captions and notes; date/media/format/tag/duration filters and multiple sort orders; batch actions. |
| Photo editing | Save reversible crop, quarter-turn rotation and straightening recipes; keep original bytes intact. |
| Import | Preserve supported original files from Files or the encrypted share-sheet inbox. Source files remain in their original apps. |
| Library tools | Inspect storage by album/item, review exact and visually similar duplicates, and optionally enable encrypted on-device text search. |
| Sharing presets | Save photo format/size/quality, video size, audio removal and optional metadata together. |
| Metadata editing | Save metadata presets and choose optional coordinates by map, search, or numeric input. |
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

**Prepare to Share** lets you draw, move and resize blur areas, zoom the canvas, undo/redo edits, and choose metadata or complete sharing presets. **Detect Sensitive Areas** offers faces, accurate text recognition and QR/barcode detection. Choose all text or a heuristic sensitive-text filter for contact details, numbers and document labels, and balanced or thorough scanning. Review and accept individual suggestions or blur all suggested areas. The editor and exported copy use the same Gaussian blur, applied to selected raster pixels before encoding. Video blur can stay fixed, follow automatic on-device tracking, or interpolate between manually edited keyframes. Trim, full audio removal and selected silent intervals are optional. Blur preserves coarse color and shape; detection and tracking can miss content. Inspect the whole exported copy. The next screen displays the encoded output, its size and metadata, and compares removed/changed fields. Batch sharing handles up to 20 copies, with a 512 MB combined export limit. Each item needs its own review for sensitive visible content.

Photo tagging, AI phrase interpretation and text indexing are **off by default**, including for existing vaults with no saved preference. Smart Search is hidden on devices that do not support Apple Intelligence. On supported devices with Apple Intelligence off or its model not ready, its entry points and AI controls are gray and disabled, with an explanation in Settings. Gallery rechecks availability when returning to the foreground; saved opt-ins cannot bypass it. Background tagging and interpretation stop when support is unavailable.

With Apple Intelligence enabled and ready, open **Library Tools → Smart Search**, or **Settings → Smart Search**, and enable **Find objects and scenes**. Apple's on-device image classifier generates English object/scene labels regardless of the device's display language. Existing and newly imported private photos are tagged while unlocked, with up to 24 labels per photo and 500 photos per batch. Work continues through remaining batches, can be paused/resumed, and stops on lock. Open a photo to review, remove or refresh its AI tags. Crop/rotation edits invalidate them. Turning Smart Search off cancels tagging and deletes its tags while retaining your own metadata and synonyms. The existing 4 MiB encrypted organization limit applies; an indexing error pauses work and is shown in Smart Search.

**Search Synonyms** lets you add, edit or remove the built-in synonym groups, or restore defaults. For example, link `sunglasses, shades, óculos de sol`. Changes apply to existing tags immediately, without retagging photos. Groups are encrypted with your library and support up to 100 groups of 2–12 terms. Search also includes your tags, captions, notes and enabled text recognition. A keyword query such as “headphones travel” retains its required travel context.

**Interpret search phrases with AI** uses Apple's local Foundation Models on eligible devices with Apple Intelligence enabled and its model ready. Free descriptions such as “the things you wear on your ears to hear music” can resolve to headphones; supported-language wording can resolve to the same English tags. This is independent of the synonym groups. English `and`, `or`, `without` and Portuguese `e`, `com`, `ou`, `sem` have deterministic subject-combination/exclusion rules; mixed AND/OR expressions are left to literal search. The UI shows the interpreted subjects and explains that actions, positions, dates, colors and other details are not verified by object tags. Ordinary matching and explicit keyword context take priority. Interpretation receives only the current subject phrase and up to 256 actual recognized label names, with no photos, captions, notes, tools, conversation history or cloud fallback. It keeps one temporary plan, clears it on lock and falls back to words/synonyms on unavailability or invalid output. Recognition and interpretation can make mistakes; this is not an exhaustive object inventory.

Albums, tags, favorites, captions, notes and photo recipes are encrypted in the vault and available only while unlocked. Search includes album names, tags, captions and notes. Optional **Private Text Search** reads text on-device and saves an encrypted transcript in the vault; disabling it deletes those transcripts. No system search index is created. Text indexing checks up to 500 photos per run. Duplicate review compares authenticated original bytes for up to 500 items and visual similarity for up to 300 photo thumbnails; select a batch to choose which items are scanned. Similarity is a suggestion, and deletion is always manual. Batch organization and deletion accept up to 500 selected items. Deleting an album keeps its media.

Saved crop/rotation/straightening recipes apply to private previews and newly shared copies. Resetting a recipe restores the original view. The storage dashboard reports encrypted item bytes, original media bytes, album totals, largest items and temporary work/export files. Items in multiple albums contribute to each album total.

### Files and incoming shares

The Files importer accepts up to 20 supported images or videos at a time, bounded to 1 GB per file and the image/video decode limits. It detects the actual media format, encrypts preserved originals and verifies them before completing an import. It never deletes the source in Files.

Gallery's share extension encrypts incoming files directly into a protected, backup-excluded App Group inbox using a public recipient key. The vault key and recipient private key remain available only to the main app. The inbox holds at most 20 files and 1 GB total; open Gallery and unlock to import or discard them. Queued files are removed only after the vault copy verifies. The extension does not unlock or expose the private library. This is a local iOS import destination; no account, relay or transfer service participates.

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
| [Smart Search and blur verification](Docs/Validation-2026-10-09-SmartSearch.md) | Object/context searches, detection, encoded blur and execution limits |
| [Search language and default-state verification](Docs/Validation-2026-10-09-SearchLanguage.md) | Editable synonyms, real local AI queries, opt-ins and hidden/gray states |
| [Library tools verification](Docs/Validation-2026-10-06-LibraryTools.md) | Earlier library feature tests and rendered screens |
| [Earlier verification record](Docs/Validation-2026-09-17.md) | Earlier tests and physical-device limits |
| [0.2.0 release notes](Docs/Release-0.2.0.md) | Build evidence and release preparation |
| [Privacy policy](Docs/PrivacyPolicy-2026-10-09.md) | Published policy for local storage, optional on-device AI, analysis and sharing |

<a id="contributing-and-security"></a>

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md) before proposing changes. Report
vulnerabilities privately using [SECURITY.md](SECURITY.md).

## License

Copyright (C) 2026 Luiz Widmer. Noct Gallery is free software licensed under
the [GNU Affero General Public License v3.0 or later](LICENSE).
