# Original FlareStorePlus b58 preview

This is an opt-in binary modification of the **original** user-supplied
FlareStorePlus b57 (bundle ID `com.Flare.FlareStore-iOS`). It is not the
separate EmberSign-based source rebuild.

## What b58 actually adds

- An unobtrusive Library-tab status label reading the original app's persisted
  `backgroundRefreshLastRun` key. It shows the localized date and time of the
  last recorded completed background refresh, or `Not run yet` when absent.
- The status updates on a 5-second in-app timer and when the app becomes active.
- It leaves the original repository refresh system, background scheduling,
  signing, installation ledger, app groups, and bundle ID untouched.
- The version/build in the original app's Info.plist is now `1.5.0 (58)`.

## Known limitations

1. **Not tested on a signed physical iPhone.** Static Mach-O dependency,
   bundle-identity and ZIP integrity tests pass; Library navigation/UI
   visibility still needs a real-device check. The indicator relies on UIKit's
   selected Library tab title, which may differ on some SwiftUI layouts.
2. This is specifically a **last background refresh** timestamp. It is not
   a claim that manually opened repositories were just synced, and it is not
   a newly scheduled background task. The original app already has background
   refresh and auto-update settings, subject to iOS scheduling and Low Power Mode.
3. The original app's **false Update badge and three-component version bug
   are still unresolved**. No version reconciliation hook was injected into
   this preview. One real installed-vs-feed app example and its signed bundle
   identity are needed to safely target the original compiled comparison.
4. The IPA is **unsigned after patching**. Sign the entire app, including the
   nested `Frameworks/FlareStorePlusRuntime.dylib`, with the same signing team
   as the existing installation. Different team IDs can prevent in-place
   upgrades and risk user data if the existing app is deleted.

## Reproducible packaging

The GitHub Actions `original-runtime-build.yml` workflow compiles only the
small injected iOS dylib; it never uploads the user's proprietary IPA.

```bash
python3 -m pip install lief
python3 patches/original_runtime/build_b58.py \
  --input /path/to/FlareStorePlus-b57-preview.ipa \
  --dylib /path/to/FlareStorePlusRuntime.dylib \
  --output /path/to/FlareStorePlus-b58-Library-preview.ipa
```

The packager checks the exact input SHA-256, preserves previous executable
patch hooks, inserts the runtime load command, verifies the original bundle
identity, and validates the output ZIP. No proprietary IPA is committed to
the repository.
