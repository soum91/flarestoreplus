# FlareStore 1.5.0 binary trace (user-supplied b55 IPA)

Read-only disassembly of ARM64 main executable. File offsets match the
0x100000000-based VM addresses in the __TEXT segment. These are **anchors**,
not a reviewed source-level call graph.

| Evidence | Literal virtual address | Nearby function |
| --- | --- | --- |
| `Install directly to device` | `0x100fc13b0` | `0x1005e76d4` |
| `Install via web manifest` | `0x100fc1390` | `0x1005e76d4` |
| `Installation Method` | `0x100fc1370` | `0x1005e76d4`, `0x1008d1c80` |
| `installLedger.v1` | `0x100fae5b0` | `0x10022cdf0`, `0x10022cf38` |
| `installedAppsCache.bundleIDs` | `0x100fae510` | `0x10022a490`, `0x10022ad44` |
| `that version is already installed` | `0x100fa8600` | `0x100153728`, `0x100392b60` |
| `autoInstallWhenSigned` | `0x100fa8850` | four AppStorage initialization sites |

At `0x1005e79f0` a SwiftUI label-rendering function branches on a
two-case mode: zero renders **Install directly to device**, one renders
**Install via web manifest**. **This does not prove that setting the same
value anywhere else safely chooses the corresponding installation backend.**
The persistent `installMode` string occurs in Swift metadata and cannot yet
be tied to a safe default-setting instruction.

The executable also contains `PublicStaging`,
`com.apple.mobile.installation_proxy`, pairing, and loopback-VPN strings,
but those do not establish that the direct route completes successfully.

## Actual iPhone install mechanism evidence

Additional literal inspection of the same executable found:

- `itms-services://?action=download-manifest&url=https://localhost.flarestore.vip:8080/download/`
- `Check your device for the installation prompt.\nKeep this sheet open until installation completes.`
- `HTTPS server must be running for iOS app installation`
- `Install aborted: local HTTPS server is not running`
- `Install tapped while a preflight is still running, ignored`
- `Install sheet: DNS lookup for localhost.flarestore.vip failed`

These strings establish that **a local HTTPS server plus OTA manifest
flow exists** and that it intentionally exposes an Install sheet and iOS
prompt. The string `Local install` appears near that flow's diagnostics.
They do **not** establish the complete dynamic call graph or prove that
*every* local install takes this branch. The user's screenshot shows
**Installation Method = Local** already, so merely switching this option or
changing its default cannot resolve the reported manual confirmation.

The device-proxy machinery may be used for Apple TV or another device
path. Treating its mere presence as proof of a same-device, promptless
installer was an unsupported assumption. A safe implementation would
need to select the actual paired/tunneled device, stage the IPA, start
`installation_proxy`, confirm the result, and only then update the ledger.

## Why no unconditional ARM64 branch patch yet

- Both backend methods need different preconditions (HTTPS for web manifest,
  usable pairing and tunnel for installation_proxy).
- Forcing a low-level branch could pass the wrong arguments or bypass the
  cross-team-install and data-preservation checks.
- Clearing `installLedger.v1` as a shortcut would lose the re-sign mapping and
  can make version detection *worse*.
- There is no debug trace from an actual failed direct install, nor the
  installed-vs-repository metadata for a false Update label.

## Minimum device evidence needed

1. Keep the already-selected **Installation Method = Local** setting.
2. Start an update of an existing signed app with pairing/VPN configured.
3. Export FlareStore **Diagnostics** for the attempt, including the last
   install and installed-app refresh lines. Redact tokens, signing credentials,
   pairing secrets, device serials, and local identifiers before sharing.
4. For one app that still shows Update after successful installation: provide
   repository version/build, the actual installed version/build, and whether
   FlareStore changed the bundle ID during signing.

With that evidence we can target the failing path, inject a narrow fix, and
regression-test the IPA without declaring a speculative patch successful.
