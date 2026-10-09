# Noct Gallery 0.5.0 — build 13

Submitted October 9, 2026 at 4:39 PM (America/Bahia).
App: `6810294404`. Bundle: `com.luizwidmer.NoctGallery`.

**App Store Connect status: Waiting for Review.** Submission
`70cda5b8-c43b-4100-8c68-89a2bb200f25` contains **0.5.0 (13)**.
Automatic release after approval and immediate availability to all users remain
selected. Apple approval and public availability of this update are pending.

The app, embedded import extension and test configurations use version 0.5.0
(13). Source changes were committed and pushed on `main` as `b066ec3` before
archiving. The earlier 0.4.0 release is a separate version.

## What's New

- Smart Search recognizes objects and scenes in your private photos on-device. Tagging and AI search are off by default. Unsupported devices hide the options; supported devices keep them gray while Apple Intelligence is off or its model isn't ready. Editable synonyms apply immediately, and eligible devices can interpret descriptions and Portuguese wording.
- More control over sensitive-area detection: faces, accurate text recognition, sensitive text, and QR/barcodes, with balanced and thorough scanning.
- Blur replaces black covers in the editor and shared photos and videos, including tracked areas and manual keyframes. Originals stay unchanged.

## Review notes

On an Apple Intelligence device with the feature enabled in system Settings and its local model ready, open the private gallery, then Library Tools → Smart Search. Tagging and AI phrase interpretation each require their own opt-in and are off initially. On unsupported devices the entry is hidden. With Apple Intelligence off or its model not ready, the entry and controls are gray and disabled; Settings explains why. Enable Find objects and scenes to tag existing and newly imported private photos while unlocked. Search for a recognized object, such as headphones or headset. Photo tags are in English regardless of device language. Search Synonyms lets you add/edit/delete groups or restore defaults; try linking sunglasses, shades, óculos de sol. Changes work without retagging. AI tags and synonyms are encrypted; tags can be reviewed/removed from photo details and are removed when Smart Search is disabled.

After enabling tagging, enable Interpret search phrases with AI and try “the things you wear on your ears to hear music,” “óculos de sol,” “dog or bicycle,” or “a bicycle without people.” The app shows the selected subjects and scope. Previously stored tags still match ordinary searches while interpretation is off or unavailable; no new tagging or inference runs while Apple Intelligence is unavailable. Simple English/Portuguese AND/OR/exclusion rules are applied by the app, and existing keyword context is preserved. No account, API key or network model is required. Recognition and interpretation are fallible; object tags do not verify actions, spatial relationships or other details.

Open a photo or video and choose Prepare to Share. Detect Sensitive Areas suggests rectangles; Detection Options controls faces, text, QR/barcodes and sensitivity. Accept individual suggestions or Blur All Suggested Areas, or draw and adjust blur regions manually. Prepare Preview renders the actual encoded copy before sharing. For videos, blur follows existing tracking/keyframes, with timestamps referring to the original clip after trimming.

## Privacy and media

[Updated privacy-policy source](PrivacyPolicy-2026-10-09.md) was published at
[the public policy page](https://luizwidmer.com/noct-gallery-privacy-policy/) and
read back in Safari. It covers opt-in English object/scene tags, editable
synonyms, on-device phrase interpretation, unavailable-device states, discarded
detection payloads and Gaussian blur. Search tags stay in the encrypted vault.
No new permissions or collection endpoints are added. The published App Store
privacy label remains **Data Not Collected**, and its privacy-policy URL is
unchanged.

[Fictional validation media and generation prompts](AIValidationMedia.md) describes the headphone, portrait, dog, bicycle, laptop and reused travel/cafe test photos. They belong only to the test bundle and are excluded from the shipping app. [Validation evidence](Validation-2026-10-09-SmartSearch.md) records native classification, context-search checks, detection and actual blur exports.

Smart Albums, backups, device transfer and Noctweave sharing remain outside this release.

[Search language and default-state verification](Validation-2026-10-09-SearchLanguage.md) records the expanded suite, actual AI interpretation and hidden/gray/off states.

## Release preparation and screenshots

The signed archive and embedded import extension were verified with matching
version/build values and App Group entitlements. Their renewed provisioning
profiles and both dSYMs are retained. Upload succeeded, App Store Connect
processed build 13, and the submitted review detail was read back to confirm
**0.5.0 (13), Waiting for Review**.

The description, promotional text, keywords, What's New and reviewer notes were
saved and read back before submission. Review notes explain PIN setup, the two
AI opt-ins, hidden/disabled states, English and Portuguese examples, blur and
export review, local processing and validation limits. Existing review contact
information and release settings are preserved.

Nine iPhone screenshots (1320 × 2868) and nine iPad screenshots (2064 × 2752)
were accepted. They show native app views with fictional generated photography;
the example media is excluded from the shipping app. The phone lock capture is
retained from the prior release because its interface is unchanged.

The sequences follow using the gallery before configuring its optional tools:

- iPhone: library → object search → photo editor → blur → export review →
  captions/notes → optional text search → Smart Search controls → unlock.
- iPad: library → object search → fullscreen viewing → photo editor → blur →
  export review → captions/notes → optional text search → Smart Search controls.

The iPhone large-display order also supplies the inherited medium-display
screenshots. Reordered assets remain in Asset Library. Apple’s optional product
page header and search-result creative assets were researched but not added.
They can be reviewed separately through Asset Library.

## Validation and private evidence

The 114-test native iOS-on-Mac suite passed, including actual Vision
classification and Apple AI inference on diverse objects. Focused iPhone and
iPad simulator checks passed with the unavailable-model inference check
explicitly skipped. Physical camera, Face ID and USB security-key execution
were not verified by this release run. See the linked validation records for
coverage and limits.

Private release evidence remains in the parent workspace at
`ReleaseArtifacts/NoctGallery-0.5.0-2026-10-09/`: archive, dSYMs, signing/upload
logs, source snapshot and hashes, test results, metadata, privacy-policy HTML,
fictional media, native captures, screenshot compositions and order manifests,
and Safari accessibility/screenshot confirmation. This directory is outside the
public repository. `screenshot-manifest-ordered.json` records the final sequence
and preserved asset hashes; `release-status.json` and
`evidence/submitted-release-ax.txt` / `evidence/submitted-release.png` record
the submitted version and build.
