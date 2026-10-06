<!-- Prepared for publication; not yet published as of this release run. -->

# Noct Gallery Privacy Policy

Draft updated October 6, 2026. Covers Noct Gallery 0.2.0 and later. Features apply when available in your installed version. This repository draft has not been published by this change.

Noct Gallery stores and processes photos and videos on your device. It has no app account, developer-operated media server, advertising SDK, analytics SDK or tracking system.

## Media and permissions

Photos access is optional and lets you browse and import selected photos and videos. Apple may download iCloud-backed originals when you open or process them. Copy and share operations leave Photos originals unchanged. An explicit Move to Private operation verifies every saved original component, then asks Apple Photos for your deletion consent. Photos deletion can propagate through iCloud Photos; Recently Deleted and external copies remain under Apple's and your control.

Files import and Gallery's share-sheet destination preserve supported source files without deleting them in the source application. The share extension encrypts incoming files into a protected local inbox using a public recipient key. Open and unlock Gallery to import or discard the queue. The extension cannot read your private library or its keys. File-provider and source applications handle your selected files under their own policies.

The private camera uses Apple's camera hardware with your permission and saves only inside Noct Gallery. Microphone permission is requested only when you choose to record sound. The app does not request your current location. Map tiles and explicit place searches use Apple Maps; Apple receives the map/search requests under its own policies. Chosen coordinates are optional metadata, not a measurement of your location.

## Private storage and authentication

Private media, thumbnails, albums, tags, captions, notes and saved photo recipes are encrypted on-device and excluded from backup. Keys, unlock configuration and sharing presets are stored in the device-only Keychain. App PINs are stored as salted, deliberately expensive verifiers, not readable PIN text. Biometric checks are performed by iOS; Gallery does not receive face or fingerprint templates. Security-key authentication is local and does not send credentials to a developer server. Required credentials have no cloud recovery service.

Optional text search uses on-device recognition and saves encrypted text in the vault only when you enable it. Turning it off removes the saved transcripts. Duplicate suggestions and video tracking also run on-device, without an external index or upload. These tools can be inaccurate and require your review.

Video conversion, playback and sharing can require temporary decrypted files protected by iOS file protection. Gallery removes these after use, on lock and during launch cleanup. A share destination receives a decrypted copy and can retain or transmit it according to that destination's policies. Gallery cannot revoke those copies.

## Choices and deletion

You can use clean copies, optional synthetic metadata, or your own saved presets. Synthetic metadata does not change identifying content visible or audible in the media. Purge and Reset removes Gallery's private files, keys, settings, incoming queue and temporary files. Optional duress PINs can reset the app or keep only selected private items; the incoming queue and its keys are cleared either way. These actions do not erase Apple Photos, previously shared copies or information retained by the operating system or hardware authenticator.

Optional tips and review requests use Apple's StoreKit and App Store systems. Gallery does not receive payment-card information. Permissions can be changed in iOS Settings. Removing the app removes its app container; use Purge and Reset first to explicitly remove its Keychain records as well.

For questions or support, contact Luiz Fernando Widmer Neto at luizwidmersupport@proton.me or visit [luizwidmer.com](https://luizwidmer.com/).
