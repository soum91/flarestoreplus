# Native reconciliation integration status

This is **real Swift source** tested as a standalone Swift Package, *not injected or linked into FlareStore's proprietary iOS executable*. FlareStore b57's current executable is unchanged.

## What the module implements
- Original repository ID to installed signed ID mapping
- Accurate version and build comparison
- An explicit pending state after IPA delivery or OTA handoff
- A confirmed receipt only after an InstalledAppQuery reports the expected signed version and build
- Prevention of silent uninstall on signing-team mismatch
- App Group-compatible persistence that replaces stale receipts for the same signed identity
- Non-destructive duplicate library entry consolidation

## Native wiring still required
1. The current SwiftUI Install/Update action must pass the actual signed IPA identity and source metadata to InstallCoordinator.start.
2. The actual FlareStore OTA installer or verified paired-device backend must implement InstallTransport. Calling an OTA manifest only yields a pending result and cannot guarantee suppression of the Apple installation prompt.
3. Implement InstalledAppQuery by querying real installed app metadata, **not** the cached signed IPA library. Obtain an authoritative source on the target iOS device; do not infer installation from HTTP 200.
4. On foreground/resume and device-install completion, call reconcile for each pending install, then trigger the installed-app cache and Update list refresh.
5. Feed confirmed receipts, including any signer-altered bundle IDs, into UpdateReconciler. Preserve user data and never silently rewrite bundle IDs or delete installed apps.

FlareStore is not publicly source-available. A valid Swift package does not make these hooks part of the shipped app. Binary-hooking arbitrary Swift functions based on string references would risk crashes and app/data loss. Do not raise the IPA build number or update the published feed until a verified native integration exists.
