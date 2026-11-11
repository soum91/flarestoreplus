# Changelog

## Original FlareStorePlus b58 Library preview - 2026-11-10

- Added a separately compiled iOS Library status extension that reads and displays the original app's recorded last background refresh, without altering background task scheduling (`e412a950`, `patches/original_runtime/FlareStorePlusRuntime.m`).
- Linked the required CoreGraphics framework and verified an arm64 dylib build on macOS Actions (`94d66198`, `.github/workflows/original-runtime-build.yml`).
- Added exact-input b57-to-b58 packaging that retains the original bundle ID and previous binary hooks, with integrity checks (`e412a950`, `patches/original_runtime/build_b58.py`).
- **Unverified:** actual display on device. **Not fixed:** the original app's false Update badges and three-component version handling. This is a personal, separately signed binary preview, not a GitHub Release or a source-rebuild IPA.

## [source-v0.1-build.10] - 2026-11-10

## Verified changes since source-v0.1-build.5

- Document original FlareStore's existing background scheduling and Library gap ([`38225122`](https://github.com/soum91/flarestoreplus/commit/38225122022458f0776ea2c5e34769dab41ee7e9); `RE_NOTES.md`)
- Preserve EmberSign plist and register background update task correctly ([`a7dd755e`](https://github.com/soum91/flarestoreplus/commit/a7dd755ef1b48aa7298ed01bbcd2692bc3da5325); `rebuilt/library_upgrade.py`, `rebuilt/test_library_upgrade.py`)
- Use stable startup anchor after EmberSign injection for background refresh ([`7c0db173`](https://github.com/soum91/flarestoreplus/commit/7c0db1733f06d02348f19ba72d5d6755f492f6d4); `rebuilt/library_upgrade.py`)
- Match library integration test to pinned EmberSign startup hook ([`a98534a1`](https://github.com/soum91/flarestoreplus/commit/a98534a172edc1a416ab9e4b6b48fde110bf30bb); `rebuilt/test_library_upgrade.py`)
- Fix background refresh initialization after EmberSign bootstrap ([`e4bfa39f`](https://github.com/soum91/flarestoreplus/commit/e4bfa39f96daa1ecfaffd7bcc0e92bf0bed0ceb3); `rebuilt/library_upgrade.py`)
- Fix Library update comparison and add timed background refresh ([`c941da2c`](https://github.com/soum91/flarestoreplus/commit/c941da2c5a2bfcab30dac8999ef62df8daadac4b); `.github/workflows/source-build.yml`, `README.md`, `rebuilt/library_upgrade.py`, and 3 more)

[Inspect exact code changes](https://github.com/soum91/flarestoreplus/compare/source-v0.1-build.5...source-v0.1-build.10)

This log records verified, release-specific changes. The [Factual release changelog](.github/workflows/release-changelog.yml) GitHub Action adds entries based on the actual commits between published releases. Entries are not fabricated for older versions that have not been audited.

