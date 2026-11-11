# Changelog

## FlareStorePlus original 1.5.1 (62) - 2026-11-11

- Removed the injected Repositories refresh text entirely after b60/b61 placed it across repository cards on device. b62 explicitly clears the label outside the Library tab.
- Preserved the working Library-tab cache/background readout. No changes to native refresh scheduling, signing certificates, installed-app registry, or auto-update selection records.
- Bumped the public app version from 1.5.0 to **1.5.1** (build 62) so FlareStore's semantic-version update detection can distinguish this release even if it ignores build numbers.
- Built the arm64 runtime with GitHub Actions; repackaged from the hash-verified original b61 IPA. Verified ZIP CRC, installed bundle identity, original executable binary, and embedded runtime SHA-256.
- Published IPA and updated the owner's existing Google Drive source.json/repo.json in place. The feed URL did not change.
- **Limitations:** requires re-signing; no real-device verification of b62. Per-app Auto-update control and false Update badge are separate unresolved items.

## FlareStorePlus original b61 - 2026-11-11

- Fixed the b60 label overlapping repository cards by removing guessed screen coordinates and the extra scroll-offset subtraction.
- Refresh text is now attached to a recognisable native search/header view in the active Repos or Library scroll hierarchy. If no safe anchor is present, it is hidden instead of covering the list.
- Replaced misleading `Last refresh` text with explicit `Cache saved` and `BG ran` timestamps. The former reflects `repositoryCacheDate`; the latter reflects `backgroundRefreshLastRun`. Neither is a verified timestamp of a successful complete fetch across all sources.
- No certificate, signing, update ledger, repository data, scheduler, or auto-update preferences were modified.
- Compiled iOS arm64 runtime in GitHub Actions, validated b60-to-b61 IPA ZIP and original executable preservation, and published b61 in the existing Google Drive JSON feed.
- **Unverified on device:** SwiftUI's search/header view might not be exposed to UIKit; in that case the readout intentionally stays hidden. Per-app auto-update toggle and accurate successful-source-refresh instrumentation are not yet implemented.

## FlareStorePlus original b60 - 2026-11-11

- Replaced b59's top-level floating status with a transparent, noninteractive label attached to the Repos/Library scrolling content.
- Read the repository's saved refresh timestamp from `repositoryCacheDate` and show the separate iOS background run time from `backgroundRefreshLastRun`. This fixes conflating the last background run with the latest repository cache update.
- Removed the b59 action sheet and its shortcuts to unrelated Settings pages. Kept the original foreground interval checks, iOS background scheduling, signing, installation ledger, and bundle identity unchanged.
- Compiled the arm64 runtime in macOS CI, verified package integrity, and published the original b60 IPA through the existing owner-controlled Google Drive source URL.
- **Open work:** native per-app Auto-update toggle on each app detail page. The original preference `autoUpdate.keys.v1` exists, but its app identity format and the original SwiftUI detail action have not been verified. No untested direct writes or fake toggle were shipped. The exact inline position still needs real-device confirmation.

## Original FlareStorePlus b59 Library controls - 2026-11-11

- Added a tappable Library status for the original app's recorded last completed background refresh, with its summary and a convenient route to the existing Settings tab.
- Exposed shortcuts for the original background-refresh and per-app automatic-update settings without creating competing schedulers or signing logic.
- Compiled the arm64 iOS runtime in macOS CI and packaged the verified owner-supplied original b58 into b59, preserving bundle identity, original executable, and declared background tasks.
- Published b59 to the owner's existing unlisted Google Drive source JSON without changing its URL.
- **Not yet device-tested:** Library button placement, original Settings navigation, or automatic installation. iOS controls when background tasks run. The earlier false Update badge remains unresolved.

## Original FlareStorePlus b58 Library preview - 2026-11-10

- Added a separately compiled iOS Library status extension that reads and displays the original app's recorded last background refresh, without altering background task scheduling (`e412a950`, `patches/original_runtime/FlareStorePlusRuntime.m`).
- Linked the required CoreGraphics framework and verified an arm64 dylib build on macOS Actions (`94d66198`, `.github/workflows/original-runtime-build.yml`).
- Added exact-input b57-to-b58 packaging that retains the original bundle ID and previous binary hooks, with integrity checks (`e412a950`, `patches/original_runtime/build_b58.py`).
- Added exact-SHA support for the owner's signed b57 IPA and verified b58 preserves all other source ZIP members (apart from executable, Info.plist, new runtime and patch manifest) ([`500ed3b2`](https://github.com/soum91/flarestoreplus/commit/500ed3b2b2a5a4658f7de03ba23cc33d3791bb81); `patches/original_runtime/build_b58.py`).
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

