# Security Model

## Invariants

1. Noct Gallery does not maintain its own media library or persist original image bytes.
2. The system Photos library is read through PhotoKit and remains the source of truth.
3. Every shared image is decoded, bounded, orientation-normalized, and re-encoded from pixels.
4. Source filenames and metadata dictionaries are never copied into a clean share export.
5. Share files use random identifiers, complete file protection, backup exclusion, and explicit cleanup.
6. Synthetic metadata is opt-in and exists only in temporary exported copies.
7. The application performs no analytics or tracking.

## What sanitization mitigates

The share pipeline removes common metadata identifiers and prevents opaque source containers from being forwarded unchanged. Encoded-size, pixel-count, and output-dimension limits reduce memory exhaustion risk. Re-encoding also removes unknown ancillary chunks and unsupported embedded payloads from the shared copy.

## What it does not guarantee

No image decoder can promise safety against every unknown operating-system vulnerability. Visible content, steganography in pixels, perceptual fingerprints, iCloud copies, screenshots, and the source retained in Photos remain outside the sanitizer’s control. The operating system and selected share destination can access the temporary export while the share sheet is active. Decoy metadata may be recognizable as synthetic and must not be treated as proof of origin or anonymity.

Report security issues privately to the repository owner. Do not include sensitive source images in a report.
