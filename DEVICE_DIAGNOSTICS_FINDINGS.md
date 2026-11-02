# iOS 27 b56 device-diagnostic findings (November 1, 2026)

User-supplied diagnostics were reviewed privately. This document intentionally **does not copy full logs, personal device identifiers, IP addresses, certificate holder names, or private signing material**.

## Observed (not inferred)

- The Settings "Local" installation route used an HTTPS server on loopback and an `itms-services` OTA manifest. iOS's appstored requested the manifest, did a HEAD on the signed IPA, then downloaded the complete IPA.
- Successful server delivery did **not** always produce an app-reported install completion event. For the Drift and VaultBridge attempts shown, no installed-version confirmation followed the completed transfer. This does not prove they failed; it means this diagnostic stream alone cannot prove success.
- For FlareStore, an "updated in place" log was followed by a new session reporting build 56. For EmberSign, an "updated in place" log and a reopen event were recorded. These show the OTA route can update apps, despite earlier suspicion that the signing-profile ID mismatch necessarily prevents installation.
- Signer logs repeated "Replaced ... with the build just signed" numerous times for a single signing attempt. This appears to iterate over duplicate local library entries; it is **not** evidence of repeated iOS installation. Investigate why the same bundle's signed copy is stored under multiple entries, and deduplicate by stable app identity and version/build.
- The app's **self-update check** reported the upstream release build 54 while b56 was already running, so it correctly offered nothing. That self-update checker is separate from the custom Google Drive source/feed.
- Background refresh was set to a 60-minute interval and explicitly deferred while Low Power Mode was on. It does not demonstrate a successful on-open refresh for every source.

## Implications for a real fix

1. **Never clear the Update action on HTTP delivery alone.** Mark install as pending after the OTA handoff, then reconcile using an authoritative installed-app query and compare the installed bundle ID, version, and build to the expected signed package. A successful OTA transfer is not an install completion callback.
2. **Keep the original-to-re-signed bundle ID mapping** for app update comparisons, and compare build numbers where marketing versions remain constant.
3. **Do not automatically rewrite bundle IDs to the profile's displayed App ID or delete installed apps.** The exact effective entitlements and app installation outcomes need verification first, and doing so could lose data.
4. For "one-tap update" on iOS, OTA install still involves an OS-managed confirmation. The presence of installation_proxy in the executable does not prove a supported, paired-device direct install is wired to this UI.
5. **Track OTA attempt state independently of signing/library state.** Only call an app update "confirmed" after observed installed-app metadata, and log errors and completion separately.

The `ota_evidence.py` module and tests classify **delivered_not_confirmed** separately from **app_reported_update**. They are diagnostic reference tooling; they are **not native IPA fixes**.

**Status:** b57 published to the unlisted Google Drive feed is unchanged. No new fixed IPA was produced from these findings.
