# Noct Gallery Privacy Policy

Updated October 6, 2026. Covers Noct Gallery 0.2.0 and later. The original library-viewing features in 0.1.0 use the same local processing approach; private storage, camera and unlock features apply when available in your installed version.

Noct Gallery stores and processes photos and videos on your device. It has no app account, developer-operated media server, advertising SDK, analytics SDK or tracking system.

## Media and permissions

Photos access is optional and lets you browse and import selected photos and videos. Apple may download iCloud-backed originals when you open or process them. Sharing and copying leave Photos originals unchanged. In version 0.2.1 and later, choosing Move to Private Gallery preserves and verifies an encrypted original before asking Photos to delete its copy. Deletion can sync through iCloud Photos. Photos retains deleted items in Recently Deleted for up to 30 days unless you remove them there. Version 0.3.0 and later can preserve supported Live Photo and RAW components. Edited, unknown or unsupported resource combinations remain in Photos.

The private camera uses Apple's camera hardware with your permission and saves only inside Noct Gallery. Microphone permission is requested only when you choose to record sound. The app does not request your current location. Map tiles and explicit place searches use Apple Maps; Apple receives the map/search requests under its own policies. Chosen coordinates are optional metadata, not a measurement of your location.

In version 0.4.0 and later, you can select supported files from Files or send them from another app using Save to NoctGallery. Your chosen Files provider may download a file before handing it to Gallery. The share extension encrypts incoming media and its type/size information in a bounded on-device App Group queue excluded from backup. The extension has only the public receiving key; it cannot read your private gallery or its unlock keys. Open and unlock Gallery to import queued items, or discard them. Gallery verifies the private copy before removing the queued copy. Reset and duress actions clear the incoming queue and its receiving keys.

## Private storage and authentication

Private media, thumbnails, item records, albums, favorites, tags, captions, notes, photo-edit recipes and enabled text-search indexes are encrypted on-device and excluded from backup. Keys and unlock configuration are stored in the device-only Keychain. App PINs are stored as salted, deliberately expensive verifiers, not readable PIN text. Biometric checks are performed by iOS; Gallery does not receive face or fingerprint templates. Required credentials have no cloud recovery service.

Optional security-key authentication works with a connected, compatible USB FIDO2 key. Gallery serves its authentication page only inside your device through a temporary localhost connection and uses Apple's ephemeral authentication browser. Challenges and signature verification remain on-device; no account, website association or remote authentication server is involved. Gallery stores the credential identifier, public key and signature counter in device-only Keychain; the authenticator retains its private key. Apple's system sheet handles the key PIN and touch for new registrations. Earlier registrations use their original local USB connection, with a PIN used only for the current attempt and never saved. Gallery has no NFC scanner; Apple's own sheet may offer NFC on capable devices.

Video conversion, playback and sharing can require temporary decrypted files protected by iOS file protection. Gallery removes these after use, on lock and during launch cleanup. A share destination receives a decrypted copy and can retain or transmit it according to that destination's policies. Gallery cannot revoke those copies.

## Local editing and suggestions

Face and text suggestions, optional text recognition, photo similarity suggestions and video motion tracking use Apple frameworks on-device. Gallery does not send images, recognized text, fingerprints or tracking results to a developer-operated service. Face/text cover suggestions do not retain text transcripts. Private Text Search is a separate opt-in feature: when enabled, recognized text is saved in the encrypted vault and used for searches while unlocked. Turning it off removes those transcripts. Duplicate fingerprints and similarity results are temporary; deletion always requires your selection.

Photo crop, rotation and straightening are reversible recipes stored encrypted; original resources remain unchanged. Covers, trimming, selected audio muting and optional full audio removal apply to shared copies. Version 0.4.0 adds moving video covers with local tracking and manual keyframes. Captions and private notes are not added to shared copies. The export preview inspects the actual encoded file. Automated suggestions and tracking can miss details; review the entire copy before sharing. These tools and metadata removal do not guarantee anonymity.

## Choices and deletion

You can use clean copies, optional synthetic metadata, or your own saved presets. Synthetic metadata does not change identifying content visible or audible in the media. Purge and Reset removes Gallery's private files, keys, settings and temporary files. Optional duress PINs can reset the app or keep only selected private items. These actions do not erase Apple Photos, previously shared copies or information retained by the operating system or a hardware authenticator.

Optional tips and review requests use Apple's StoreKit and App Store systems. Gallery does not receive payment-card information. Permissions can be changed in iOS Settings. Removing the app removes its app container; use Purge and Reset first to explicitly remove its Keychain records as well.

## Support and policy updates

If you contact us, we receive the email address, message and attachments you choose to send. We use this information to answer your request and retain relevant support records. Our email provider processes that correspondence. Please do not send PINs, passwords, private keys or unnecessary private media. Visiting our support website is separate from using Gallery and is covered by the website privacy policy. The app does not collect personal information from children for advertising or tracking. We may update this policy when app behavior changes.

For questions or support, contact Luiz Fernando Widmer Neto at luizwidmersupport@proton.me or visit [luizwidmer.com](https://luizwidmer.com/).

[Apple privacy information](https://www.apple.com/legal/privacy/) · [Website privacy policy](https://luizwidmer.com/privacy-policy/)
