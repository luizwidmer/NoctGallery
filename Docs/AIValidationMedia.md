# Fictional validation media

Generated October 9, 2026 with the built-in imagegen tool; generate mode, opaque background. These photos are test resources only and are not included in the shipping app. The original generated PNGs are preserved outside the repository; JPEG fixtures are resized to 1,024 pixels for bounded tests.

## Headphones

Saved fixture: `NoctGalleryTests/TestMedia/headphones.jpg`.

Prompt:

Use case: product-mockup. Asset type: fictional photo fixture for a private gallery's on-device object recognition and contextual search. Create a crisp photorealistic square image of a pair of matte black over-ear headphones lying diagonally on a warm oak desk, with their padded headband and both ear cups fully visible and occupying most of the frame. Soft natural window light, realistic leather and metal textures, uncluttered neutral background, high detail. No people, no brands, no logos, no lettering, no watermark. This should look like a real personal photograph, not a diagram or UI.

## Portrait

Saved fixture: `NoctGalleryTests/TestMedia/portrait.jpg`.

Prompt:

Use case: fictional app test photography. Create a photorealistic square portrait photograph of one entirely fictional adult woman in her early thirties, looking directly at the camera with a relaxed neutral smile. Her entire head, hair, ears, shoulders, and face must be clearly visible, upright and centered, occupying about half the image width. Warm natural window light in a quiet cafe, soft out-of-focus background, casual forest-green shirt. Realistic skin texture. No headphones, no other people, no text, no logo, no watermark, no UI. This image will be used as disposable fictional media to test on-device face detection in a private gallery app.

The QR code used by the detection tests is generated deterministically with Core Image from a fictional example.test URL. No customer photos or personal data are used.

## Additional objects

The following images were generated in the same session for the broader object-search checks. Original PNG files remain under the Codex generated-images folder.

### dog

Fixture: `NoctGalleryTests/TestMedia/dog.jpg`.
Original: `exec-06b118ff-5f03-4f83-9b63-d2b4658d65ae.png`.

Prompt:

Use case: fictional photography fixture for on-device object recognition. Make a crisp photorealistic square photograph of one golden retriever dog standing on a green lawn in daylight. The whole dog is visible in side view with its head turned gently toward the camera, occupying most of the frame. Natural golden fur, paws, tail, ears and muzzle clearly distinguishable. Simple lawn and soft garden background. No humans, collar lettering, brands, logos, text, UI or watermark. A natural personal photo, not an illustration.

### bicycle

Fixture: `NoctGalleryTests/TestMedia/bicycle.jpg`.
Original: `exec-a7455a34-ea73-46cd-88f0-88884972ed0c.png`.

Prompt:

Use case: fictional photography fixture for on-device object recognition. Make a crisp photorealistic square photograph of a complete matte teal city bicycle leaning against a plain warm stone wall on a sidewalk. Both wheels, frame, handlebars, seat, pedals and chain are clearly visible in side view, occupying most of the frame. Soft daylight and realistic metal, rubber and stone textures. Uncluttered background, no people, brands, logos, text, UI or watermark. A natural personal photo, not an illustration.

### laptop

Fixture: `NoctGalleryTests/TestMedia/laptop.jpg`.
Original: `exec-f73ddb89-2fd1-4cfc-93b2-10d143e0d2d8.png`.

Prompt:

Use case: fictional photography fixture for on-device object recognition. Make a crisp photorealistic square photograph of an open unbranded silver laptop computer on a simple oak desk, viewed from a clear three-quarter angle. The keyboard, trackpad, thin portable body and raised screen are fully visible and occupy most of the frame. The screen shows an abstract blue-green wallpaper without letters or app windows. Soft natural daylight, realistic aluminum and glass, plain light wall background. No people, other devices, brands, logos, lettering, UI, or watermark. A natural personal photo, not an illustration.

## Reused fictional travel and cafe photos

`coffee.jpg`, `sunglasses.jpg` and `lake.jpg` are JPEG derivatives of the generated cafe, itinerary and mountain/lake photographs used for the 0.4.0 screenshot review. Their preserved source media and prompts are described in [the earlier release record](Release-0.4.0.md). These copies are now test-bundle resources so the classifier regression test works without local marketing artifacts.

### Reused media prompts

**coffee.jpg** (source: cafe)

Use case: photorealistic-natural. Asset type: fictional sample photo inside a private photo gallery App Store screenshot. Create one beautiful 4:3 landscape editorial lifestyle photograph at a neighborhood cafe: a ceramic cappuccino cup with realistic delicate latte art on a sunlit round travertine table, flaky croissant on a small ivory plate, soft linen, eucalyptus shadow from left, warm ochre and muted sage tones, shallow depth of field, calm morning atmosphere. Realistic imperfect textures and soft natural light, considered but candid phone-camera feel. No people, no lettering, no logos, no watermark, no borders, no collage, no UI. Single photograph.

**sunglasses.jpg** (source: itinerary)

Use case: photorealistic-natural. Asset type: fictional private-gallery photo to demonstrate text search and covering details in actual app screenshots. Create a tasteful realistic 4:3 photograph looking straight down at a cream paper travel booking card lying on a muted teal desk beside a corner of a linen notebook and sunglasses. Beautiful natural window light, elegant typography, realistic paper texture, uncluttered. Card has large clear legible text: 'LISBON WEEKEND', then 'Maya Costa', then 'Booking  L9Q8N2', then '12 OCT — 15 OCT', then small text 'Harbor House · Courtyard Suite'. This is an entirely fictional hotel itinerary for a demonstration gallery, no logos, no government documents, no QR or barcodes, no passport, no watermark, no demo/sample/test labels, no borders, no UI. Keep full card within the central 80 percent of the image and booking line clearly readable in its middle. Single photographed scene.

**lake.jpg** (source: mountains)

Use case: photorealistic-natural. Asset type: fictional sample photo inside a private photo gallery App Store screenshot. Create a beautiful 4:3 landscape outdoor travel photograph of a quiet alpine lake at sunrise, dark pine forest along the shoreline, a tiny cedar wooden dock in foreground, mountain peaks lightly dusted with snow, mist above teal water with golden sky reflection. Natural realistic fine textures, cinematic but believable mobile travel photography, balanced composition, muted green and amber palette. No people, no lettering, no logos, no watermark, no borders, no collage, no UI. Single photograph.

## Genuine native classifications

`native-vision-classifications.json` contains actual Apple Vision output captured by `GalleryVisualFixtureTests` in the native iOS-on-Mac review app. It is used only to pre-index the disposable Simulator screenshot vault, because the installed iOS 26.5 Simulator classifier gives incorrect labels. The functional recognition tests call the real classifier afresh on all eight photos; they do not use this JSON. Neither the JSON nor any test photo is present in the release application or share extension.

[The verification record](Validation-2026-10-09-SmartSearch.md) lists the positive and unrelated queries, execution platforms and their limits.
