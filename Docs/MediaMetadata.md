# Media metadata design and reference catalog

Reviewed 2026-09-17. These are synthetic profiles, not authentic camera exports or an anonymity guarantee. Clean is the private camera default. A finite catalog, encoding characteristics and visible content can still identify patterns. Increasing the catalog is only a reduction in repetition.

## What is written

A photo is decoded, orientation-normalized and encoded from a fresh sRGB raster. Clean output omits optional source metadata. A decoy can add TIFF make/model/date, EXIF exposure/ISO/aperture/focal length/date and offset, plus optional GPS. Turning off **Include camera metadata** omits make, model, exposure and lens fields while retaining the chosen date and optional GPS. Serial numbers, owner names, firmware strings, MakerNotes, comments and source metadata are never copied.

A movie is decoded and re-encoded to H.264/AAC MOV. Its optional decoy tags are make, model, creation date and ISO 6709 coordinates. Photo exposure/lens controls are hidden for video, because those tags are not written into the movie. QuickTime movie/track/media creation and modification fields are cleared for clean exports or set to the selected date. The first video and optional first audio track are retained; extra tracks and opaque metadata are not remuxed.

EXIF local timestamps and offset tags describe the same instant as UTC GPS date/time. Search-selected map places supply a time zone; manually dropped pins use GMT. Dates without GPS have an independently editable time zone. Presets retain a time offset, so successive camera captures advance naturally.

Standards and API references: [CIPA Exif 3.0 overview](https://www.cipa.jp/std/documents/e/Exif3.0-Overview_E.pdf), [Apple QuickTime creation time](https://developer.apple.com/documentation/quicktime-file-format/movie_header_atom/creation_time), [AVAssetWriter](https://developer.apple.com/documentation/avfoundation/avassetwriter), and [MapReader](https://developer.apple.com/documentation/mapkit/mapreader). The Exif reference documents field semantics; it is not a claim that version 3.0 is the latest standard.

## Equipment provenance

The catalog contains **21 models, eight manufacturers and 40 camera/lens combinations**. Zoom entries use published wide/tele endpoints rather than inventing intermediate focal/aperture pairs. All listed models predate the conservative January 2024 minimum capture date.

| Models | Implemented optics | Primary reference |
|---|---|---|
| iPhone 14 Pro, 14 Pro Max | Main 24 mm equivalent f/1.78; ultra-wide 13 mm f/2.2; tele 77 mm f/2.8 | [14 Pro](https://support.apple.com/en-is/111849), [14 Pro Max](https://support.apple.com/zh-hk/111846) |
| iPhone 15, 15 Plus | Main 26 mm equivalent f/1.6; ultra-wide 13 mm f/2.4 | [15](https://support.apple.com/en-au/111831), [15 Plus](https://support.apple.com/en-au/111830) |
| iPhone 15 Pro, 15 Pro Max | Main 24 mm equivalent f/1.78; ultra-wide 13 mm f/2.2; tele 77 or 120 mm f/2.8 | [15 Pro](https://support.apple.com/en-au/111829), [15 Pro Max](https://support.apple.com/en-au/111828) |
| Fujifilm X100V, X100F | 23 mm physical / 35 mm equivalent, f/2 | [X100V manual](https://fujifilm-dsc.com/en/manual/x100v/technical_notes/spec/index.html), [X100F specifications](https://www.fujifilm-x.com/en-au/products/cameras/x100f/) |
| Fujifilm XF10 | 18.5 / 28 mm, f/2.8 | [XF10 manual](https://fujifilm-dsc.com/en/manual/xf10/technical_notes/spec/index.html) |
| Ricoh GR III, GR IIIx | 18.3 / 28 mm and 26.1 / 40 mm, f/2.8 | [Ricoh specifications](https://www.ricoh-imaging.co.jp/english/products/gr-3/spec/) |
| Sony RX100 III, RX100 V | Wide 8.8 / 24 mm f/1.8; tele 25.7 / 70 mm f/2.8 | [RX100 III](https://www.sony.com/electronics/support/compact-cameras-dsc-rx-series/dsc-rx100m3/specifications), [RX100 V](https://www.sony.com/electronics/support/compact-cameras-dsc-rx-series/dsc-rx100m5/specifications) |
| Sony RX100 VII | Wide 9 / 24 mm f/2.8; tele 72 / 200 mm f/4.5 | [Sony specifications](https://www.sony.com/electronics/support/compact-cameras-dsc-rx-series/dsc-rx100m7/specifications) |
| Sony RX1R II | 35 / 35 mm, f/2 | [Sony specifications](https://www.sony.com/electronics/support/compact-cameras-dsc-rx-series/dsc-rx1rm2/specifications) |
| Canon PowerShot G7 X II, G5 X II | Wide 8.8 / 24 mm f/1.8; tele 36.8 / 100 mm or 44 / 120 mm f/2.8 | [G7 X II](https://asia.canon/en/support/6200338100), [G5 X II](https://asia.canon/en/support/6200620100) |
| Panasonic LX100, LX100 II | Wide 10.9 / 24 mm f/1.7; tele 34 / 75 mm f/2.8 | [LX100](https://help.na.panasonic.com/answers/features-and-specifications-lumix-point-shoot-dmc-lx100/), [LX100 II](https://help.na.panasonic.com/answers/features-and-specifications-lumix-point-shoot-dc-lx100m2/) |
| Leica D-Lux 7 | Wide 10.9 / 24 mm f/1.7; tele 34 / 75 mm f/2.8 | [Leica manual](https://leica-camera.com/sites/default/files/pm-73002-Leica-D-Lux-7_Instructions_en.pdf) |
| Nikon COOLPIX P1000 | Wide 4.3 / 24 mm f/2.8; tele 539 / 3000 mm f/8 | [Nikon specifications](https://www.nikon-asia.com/digital-camera-coolpix-p1000-ep-bk-sg) |

Phone physical focal lengths are omitted because these Apple specifications publish equivalents, not physical EXIF lens calibration. Phone aperture stays fixed. Phone ISO/shutter pools are curated plausible values, not a claim that every phone firmware emits those exact values. The catalog's make/model labels are not a byte-for-byte firmware metadata signature.

Compact-camera exposure choices use a conservative subset: apertures through f/8, shutter speeds from 1/15 to 1/1000 second, native-base ISO through 6400 (1600 for P1000). This avoids relying on aperture-dependent maximum leaf-shutter speeds, extended sensitivity modes or ND-filter state. These are not full camera capability ranges. Exposure is manually editable within this subset; scene labels guide random generation, not source-image analysis.

## Random generation

Production uses `SystemRandomNumberGenerator`. It samples a model first, then a documented lens, so models with more lens entries do not dominate. Exposure tuples are filtered by EV100 = log2(f-number² × shutter denominator × 100 / ISO): daylight 12–16, shade 8–12, indoors 4–8. It varies the capture instant within the previous year, bounded by January 2024, and keeps generated daylight/shade times between 10:00 and 16:00 in the chosen time zone. This is a plausibility heuristic, not a weather, solar-position or scene-content model.

GPS is **off by default**, including random captures. If enabled, the user can choose a center on the map and an area radius, or use 40 built-in world regions. Coordinates are sampled across the area with a randomized bearing and area-weighted distance; city centers are not repeatedly emitted. These regions are choices, not population weights or a location-anonymity dataset. Points can fall on water/private land, and a radius crossing a time-zone border retains the center's zone. The UI explains this limitation. Current device location is never read.

Disabling **Include camera metadata** avoids claiming any catalog equipment. Clean stripping remains the option with the fewest optional claims. Randomizing dates or equipment cannot hide identifiable pixels/audio, source resolution, codec artifacts, pre-existing copies or the fact that media was processed. Do not describe this as forensically indistinguishable or untraceable.

## Compatibility and verification

Optional profile fields preserve decoding of earlier saved presets. The original three profiles retain their legacy exposure values. New profiles persist the sampled exposure, inclusion flags and time zone; reopening a preset does not regenerate them. Validators reject unsupported equipment, incompatible exposure, invalid coordinates/time zones and future dates.

Tests exercise 2,000 seeded profiles, all catalog models/lenses, more than 500 distinct exposure combinations, date/light compatibility, 200 unique coordinates within a chosen 5 km radius including dateline wrapping, legacy decoding, manual-exposure persistence, tag omission and source-tag stripping. See the dated validation record for executed results and physical-test limits.
