# Noct Gallery 0.5.0 — build 13

Local development release. The app, share extension and test configurations use version 0.5.0 (13). This version has not been uploaded to App Store Connect or submitted for review. The earlier 0.4.0 submission is a separate release.

## What's New

- Smart Search recognizes objects and scenes in your private photos on-device. Tagging and AI search are off by default. Unsupported devices hide the options; supported devices keep them gray while Apple Intelligence is off or its model isn't ready. Editable synonyms apply immediately, and eligible devices can interpret descriptions and Portuguese wording.
- More control over sensitive-area detection: faces, accurate text recognition, sensitive text, and QR/barcodes, with balanced and thorough scanning.
- Blur replaces black covers in the editor and shared photos and videos, including tracked areas and manual keyframes. Originals stay unchanged.

## Review notes

On an Apple Intelligence device with the feature enabled in system Settings and its local model ready, open the private gallery, then Library Tools → Smart Search. Tagging and AI phrase interpretation each require their own opt-in and are off initially. On unsupported devices the entry is hidden. With Apple Intelligence off or its model not ready, the entry and controls are gray and disabled; Settings explains why. Enable Find objects and scenes to tag existing and newly imported private photos while unlocked. Search for a recognized object, such as headphones or headset. Photo tags are in English regardless of device language. Search Synonyms lets you add/edit/delete groups or restore defaults; try linking sunglasses, shades, óculos de sol. Changes work without retagging. AI tags and synonyms are encrypted; tags can be reviewed/removed from photo details and are removed when Smart Search is disabled.

After enabling tagging, enable Interpret search phrases with AI and try “the things you wear on your ears to hear music,” “óculos de sol,” “dog or bicycle,” or “a bicycle without people.” The app shows the selected subjects and scope. Previously stored tags still match ordinary searches while interpretation is off or unavailable; no new tagging or inference runs while Apple Intelligence is unavailable. Simple English/Portuguese AND/OR/exclusion rules are applied by the app, and existing keyword context is preserved. No account, API key or network model is required. Recognition and interpretation are fallible; object tags do not verify actions, spatial relationships or other details.

Open a photo or video and choose Prepare to Share. Detect Sensitive Areas suggests rectangles; Detection Options controls faces, text, QR/barcodes and sensitivity. Accept individual suggestions or Blur All Suggested Areas, or draw and adjust blur regions manually. Prepare Preview renders the actual encoded copy before sharing. For videos, blur follows existing tracking/keyframes, with timestamps referring to the original clip after trimming.

## Privacy and media

[Updated privacy-policy source](PrivacyPolicy-2026-10-09.md) is prepared for publication with this release; the live policy has not been changed. All classification and sensitive-area detection use local Apple frameworks. Search tags stay in the encrypted vault; detection text and code payloads are discarded. No new permissions or collection endpoints are added.

[Fictional validation media and generation prompts](AIValidationMedia.md) describes the headphone, portrait, dog, bicycle, laptop and reused travel/cafe test photos. They belong only to the test bundle and are excluded from the shipping app. [Validation evidence](Validation-2026-10-09-SmartSearch.md) records native classification, context-search checks, detection and actual blur exports.

Smart Albums, backups, device transfer and Noctweave sharing remain outside this release.

[Search language and default-state verification](Validation-2026-10-09-SearchLanguage.md) records the expanded suite, actual AI interpretation and hidden/gray/off states.
