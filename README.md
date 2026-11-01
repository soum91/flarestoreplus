# FlareStorePlus

Private, independent patch tooling for a user-provided FlareStore iOS IPA. This repository is **not** the original FlareStore source code and is not affiliated with its publisher.

## Priority fixes

1. **Update detection:** match a repository's original bundle ID to the installed, possibly re-signed ID; compare versions correctly; clear Update only after confirmed installation. `version_status.py` and its tests are a reference implementation, **not yet injected into the IPA**.
2. **Direct install:** use the already-present FlareStore `installation_proxy` route with a valid pairing record and on-device tunnel, wait for actual installation completion, then refresh the install ledger. This path is present in the binary, but its integration with the Update action is still under investigation.

The lower-priority Zeus-style details page is deferred.

## Existing test artifacts

- b55: repository sort persistence and foreground repository refresh, patched binary with `__FSPATCH`. Not device-verified.
- b56: retains b55 changes and defaults the existing **Auto Install When Signed** preference to on. This merely shows the web-install prompt automatically; it does **not** select the direct installer or dismiss an iOS prompt.

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

## Reverse-engineering notes

The supplied v1.5.0 binary contains all of:

- `InstalledAppsCache` and `installedAppsCache.bundleIDs`
- `installLedger.v1`, `appVersion`, and `CFBundleShortVersionString`
- `Installation Method` settings: `Install via web manifest` / `Install directly to device`
- `PublicStaging`, `com.apple.mobile.installation_proxy`, and loopback pairing/VPN components

Binary strings alone **do not prove** that those paths are correctly wired or available on a particular device. We still need paired-device diagnostics for the direct path and installed-vs-repository snapshots for the update bug.

