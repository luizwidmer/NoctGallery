# Contributing to Noct Gallery

Contributions should preserve the app's no-vault design: PhotoKit remains the
source of truth, and private copies are created only as bounded temporary share
exports.

## Build and test

Use Xcode 26.6 or newer with the iOS 26 SDK. Build and run the test suite with
the commands documented in `README.md`.

## Change requirements

- Never persist original media in app-managed storage.
- Strip source metadata and filenames from clean exports.
- Keep decoy metadata explicit and opt-in.
- Bound decode size, pixel count, output dimensions, and temporary-file life.
- Add tests for sanitization, metadata generation, and cleanup behavior.
- Update `README.md` and `SECURITY.md` when privacy boundaries change.
- Keep signing data, local Photos content, and generated build output out of Git.

Report vulnerabilities privately according to `SECURITY.md`.

## License of contributions

By submitting a contribution, you agree that it may be distributed under the
GNU Affero General Public License v3.0 or later (`AGPL-3.0-or-later`).
