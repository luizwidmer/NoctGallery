# Contributing to Noct Gallery

Contributions should preserve the app's local encrypted-vault design. Photos
originals are changed only by an explicit, verified Move to Private operation;
sharing creates bounded temporary exports.

## Build and test

Use Xcode 26.6 or newer with the iOS 26 SDK. Build and run the test suite with
the commands documented in `README.md`.

## Change requirements

- Encrypt every persistent app field, including original media components,
  thumbnails, manifests, album names and tags. Keep keys separate from files.
- Verify every original resource before requesting Photos deletion; reject
  unsupported combinations without dropping components.
- Strip source metadata and filenames from clean exports.
- Keep decoy metadata explicit and opt-in.
- Bound decode size, pixel count, output dimensions, and temporary-file life.
- Add focused tests for sanitization, resource preservation, redaction,
  encrypted organization, lock/duress transitions and cleanup behavior.
- Keep practice mode isolated from real media and credentials.
- Update `README.md` and `SECURITY.md` when privacy boundaries change.
- Keep signing data, local Photos content, and generated build output out of Git.

Report vulnerabilities privately according to `SECURITY.md`.

## License of contributions

By submitting a contribution, you agree that it may be distributed under the
GNU Affero General Public License v3.0 or later (`AGPL-3.0-or-later`).
