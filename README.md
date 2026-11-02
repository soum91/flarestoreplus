# FlareStorePlus

Private, independent patch tooling for a user-provided FlareStore iOS IPA. This repository is **not** the original FlareStore source code and is not affiliated with its publisher.

## Priority fixes

1. **Update detection:** match a repository's original bundle ID to the installed, possibly re-signed ID; compare versions correctly; clear Update only after confirmed installation. `version_status.py` and its tests are a reference implementation, **not yet injected into the IPA**.
2. **Direct install:** replace the iPhone's current OTA-manifest installation flow with a confirmed device-install flow, if the available pairing/tunnel stack supports it. The binary contains `installation_proxy` code, but that does **not** establish that the iPhone Install action calls it. The direct install Python module is a reference state machine, not an integrated backend.

The lower-priority Zeus-style details page is deferred.

## Existing test artifacts

- b55: repository sort persistence and foreground repository refresh, patched binary with `__FSPATCH`. Not device-verified.
- b56: retains b55 changes and defaults the existing **Auto Install When Signed** preference to on. This merely shows the web-install prompt automatically; it does **not** select the direct installer or dismiss an iOS prompt.
- b57 preview: retains exactly the b56 executable, sets display name **FlareStorePlus**, and increments the build to 57. **Branding only**. Do not describe b57 as containing the unfinished critical fixes.

## Build the b56 test patch

Obtain the b55 IPA separately from the lawful source already supplied by the user. Do not commit it here. Then run:

```bash
python3 -m pip install lief capstone
python3 patches/build_b56.py \
  --input /path/to/FlareStore-b55-sort-refresh-test.ipa \
  --output /path/to/FlareStore-b56-auto-install-prompt-test.ipa
python3 -m unittest discover -s tests -v
```

Build outputs have modified Mach-O bytes and need re-signing before installation. There is currently no evidence of an end-to-end successful iPhone update with these patches. Do not distribute the publisher's IPA or included signing material without applicable rights.

## Private preview package and JSON feed

Repackage the previously validated b56 IPA as a separately identified preview:

```bash
python3 patches/build_b57.py \
  --input /path/to/FlareStore-b56-auto-install-prompt-test.ipa \
  --output /path/to/FlareStorePlus-b57-preview.ipa
```

Once the preview IPA has been hosted at an HTTPS **direct-download** link,
generate a FlareStore-compatible feed:

```bash
python3 tools/make_feed.py \
  --ipa /path/to/FlareStorePlus-b57-preview.ipa \
  --url https://your-download-host.example/FlareStorePlus-b57-preview.ipa \
  --date 2026-11-01 \
  --output repo.json
```

The URL in the example is illustrative only. **Do not publish a JSON that
points to a missing asset or authenticated private GitHub release.** A link-only
distribution feed is *unlisted*, not access-controlled. An unlisted JSON can
keep the feed out of discovery but cannot prevent a recipient forwarding its
IPA download URL. Preserve the publisher's distribution rights and never
publish signing certificates, keys, provisioning files, or user identifiers.

## Reverse-engineering notes

See [RE_NOTES.md](RE_NOTES.md) for verified literal references, function
addresses, and the remaining device-evidence requirement.

The supplied v1.5.0 binary contains all of:

- `InstalledAppsCache` and `installedAppsCache.bundleIDs`
- `installLedger.v1`, `appVersion`, and `CFBundleShortVersionString`
- `Installation Method` settings: `Install via web manifest` / `Install directly to device`
- `PublicStaging`, `com.apple.mobile.installation_proxy`, and loopback pairing/VPN components
- An `itms-services://` OTA manifest for `https://localhost.flarestore.vip:8080/download/`, an install sheet, and local HTTPS install-server diagnostics

Crucially, the screen label **Install directly to device** does not itself prove that this setting bypasses OTA. The compiled application includes both device-proxy machinery and a local-server/manifest flow; only a device trace can establish which backend handled a given action. The user's screenshot already confirms that **Local** is selected. We still need diagnostics for that actual install action and installed-vs-repository snapshots for the update bug.

