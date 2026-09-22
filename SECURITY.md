# Security model

## Storage and access

The private gallery encrypts media, thumbnails and item records using CryptoKit AES-256-GCM. Each item derives a distinct key from a random master key with HKDF-SHA256. Large media uses bounded 1 MiB chunks, with authenticated data binding the item identifier, chunk index and total size. Truncation, reordering, modification and appended data are rejected. Imports become visible only after an atomic directory move. A missing key does not silently replace an existing gallery.

The master key and app-protection configuration are stored in separate non-synchronizing Keychain records using `WhenUnlockedThisDeviceOnly`. PIN verifiers use independent random salts and PBKDF2-HMAC-SHA256 with 600,000 iterations. A persisted retry ledger adds increasing delays after five failed attempts; restarting the app does not clear it. PIN text is not persisted or logged.

App protection gates the whole interface, private-media access and camera. All configured factors must succeed in the current attempt in Key → Biometrics → PIN order. The biometric policy is `deviceOwnerAuthenticationWithBiometrics`, without device-passcode fallback. Biometric enrollment remains managed by iOS. A key is verified cryptographically with user presence and user verification, fresh challenges, signature checks and counters through the public NoctweaveSecurityKeys package.

New FIDO2 registrations use RP `localhost` through an ephemeral `ASWebAuthenticationSession`. Gallery binds only `127.0.0.1` on an OS-assigned port and serves a bundled page at a random 256-bit path. No hosted service, associated domain, external assets, or app outbound requests participate. Native verification pins the exact `http://localhost:<bound-port>` origin, challenge, RP hash, credential ID, ES256 signature, UP/UV flags, and monotonic counters (including authenticators that always return zero). Platform and backup credentials are rejected. Registration is provisional until a separate fresh assertion proves possession.

The listener bounds headers, body sizes, connection counts and deadlines; rejects duplicate headers, ambiguous framing and pipelining; requires the exact Host and same-origin result POST; and accepts one result per ceremony. The browser callback must match the session token and a received response. It is only a completion signal, never an unlock proof. Cancellation, timeout and background locking close the listener and invalidate the attempt. Key PIN entry stays in Apple's sheet. Credential IDs, public keys and counters remain in device-only Keychain. See [the local FIDO2 design and trust boundary](Docs/LocalFIDO2.md).

Gallery has no NFC usage description, NFC entitlement, or scanner UI. Apple's browser owns its transport sheet and may offer NFC on capable devices; USB is requested for assertions. Existing `.invalid` registrations retain the original USB smart-card SDK path (FIDO over CCID, YubiKey 5.8+), limited to USB before a connection opens. They are not rewritten as localhost credentials. No continuous-presence promise is made.

Discreet mode requires an existing duress PIN. It presents only a PIN field; a two-second hold on the Gallery logo starts the ordinary factor chain. It does not automatically prompt biometrics. The logo has no accessibility label exposing the gesture. Once deliberately triggered, system biometric or key prompts necessarily reveal the chosen method. This concealment is a UI behavior, not a guarantee against inspection, observation or coercion. Removing the last duress PIN disables discreet mode.

These are local app access controls. Factors do not each contribute independent encryption material to the media key. This is not a defense against a compromised OS, debugger attached to a development build, modified app binary, an attacker controlling the Keychain, or arbitrary execution inside the unlocked process. Swift memory management does not guarantee forensic zeroization of every previous plaintext allocation.

The app covers inactive scenes, locks on backgrounding and discards its active media key, private item list, image cache and decrypted work files. Pending conversions are cancelled and closed before scratch cleanup. The iOS app switcher cover is not a guarantee against screenshots or screen recording taken while unlocked.

## Private capture, playback and sharing

AVFoundation captures directly to app storage without any PhotoKit write call. The built-in Apple camera app is not opened. Camera access is requested when opening the private camera, and microphone access only when recording with sound. Hardware permissions and camera/microphone indicators still apply.

All persistent private records and thumbnails are encrypted. Video capture, conversion, playback and sharing can require short-lived plaintext files under complete file protection and backup-excluded directories. Paths use random identifiers. Closing playback, locking, completed/cancelled sharing and launch cleanup remove those files. An interrupted capture is never imported as a saved item. The operating system and the share destination can read an authorized export while it exists; Gallery cannot revoke a copy already received.

## Metadata

Still images are decoded with size limits, orientation-normalized, converted to an sRGB raster and re-encoded into a fresh container. Clean exports do not copy source EXIF, GPS, TIFF, IPTC, XMP, MakerNotes, serials, software strings or opaque ancillary payloads.

Video processing decodes the first video track and optional first audio track into fresh H.264/AAC. Source metadata and ancillary tracks are not remuxed. Rotation is applied to pixels. Output tags are read back and checked against an explicit allowlist. QuickTime creation/modification fields in movie, track and media headers are cleared for clean exports or set to the chosen decoy date. Duration and sample timing remain intact.

Synthetic profiles contain chosen documented equipment, curated exposure settings and optional GPS. Random profiles span 21 models, use varied compatible settings and times, and omit GPS by default. Optional GPS varies within an area, rather than repeating fixed pins. Equipment tags can be omitted entirely while rewriting date/location. A larger finite catalog still has recognizable distributions; it is not an anonymity set. They do not promise an authentic firmware fingerprint. Visible content, audio, steganography, perceptual fingerprints, device codec behavior and filesystem timestamps are outside metadata stripping. Every source decoder also remains subject to unknown operating-system vulnerabilities.

## Duress and reset

A configured duress PIN can act before any ordinary factor. Two actions are available: clear the private gallery and settings, or retain only the explicitly selected private items. The matched PIN becomes the sole normal unlock credential; previous PIN, key credentials, biometrics, duress definitions and decoy-selection labels are removed. Reset returns to Finish Onboarding with the replacement PIN already established. Retained decoys remain ordinary editable, playable and shareable items.

Before an action starts, a bounded plan is committed in device-only Keychain. The app blocks ordinary unlocking while the plan exists. Retained items are authenticated and re-encrypted in bounded memory with a fresh master key into protected staging storage. Directory swaps and ready markers allow replay after interruption. The old persistent media key is replaced and the old ciphertext is removed. A failed write or unavailable protected file blocks completion and is retried before content opens. Corruption in a retained item fails closed. Deleted or no-longer-selected items are not resurrected.

Purge and Reset removes Gallery's private files, its keys, unlock settings, presets, scratch and export files. It requires explicit destructive confirmation in the interface, including from the lock screen when credentials are lost. A pending reset marker survives failure and is completed at launch. Neither reset nor duress erases Apple Photos, external copies, hardware-key credentials stored on the physical authenticator, OS forensic snapshots or flash remnants. Key rotation is not a promise of secure physical erasure.

## Network and reporting

No media is sent to a developer-operated server. PhotoKit may use iCloud, maps/search contact Apple, and StoreKit communicates with Apple. There is no advertising, analytics or tracking SDK. The app never requests current location.

Report vulnerabilities privately to the repository owner. Use disposable fixtures and never attach sensitive photos, key PINs or private media keys to a report.
