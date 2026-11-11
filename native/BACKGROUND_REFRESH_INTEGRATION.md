# Original-app background refresh: integration boundary

## Evidence, November 11, 2026

Device screenshot: eight of ten recent BG refresh launches ended early with
"ended by iOS while fetching sources"; two completed 33 sources in ~19 seconds.
The original Mach-O contains `BackgroundRefreshManager`,
`RepositoryViewModel`, `fetchAllRepositoriesInternal`, `fetchBatchSize`,
and an existing batch log string. Therefore **the original already batches
network requests**, but the background workflow still tries all 33 sources in
a short iOS task. Merely changing the UI or adding another BG scheduler
does not solve this.

## Implemented and tested

`Sources/FlareStorePlusCore/CheckpointedBackgroundRefresh.swift` implements
an opt-in engine intended for the native host integration:

- Batch defaults: 8 source IDs and 18 seconds, with a 2-second safety margin.
- Atomic progress checkpoint after each committed source and after failed
  fetches; resumed runs do not re-fetch successful sources in the same cycle.
- Failing sources rotate to the back rather than blocking healthy sources.
- Per-source deadlines and cooperative cancellation contract for URLSession.
- Added/removed repositories reconcile with the persisted pending queue.
- Full completion is reported only when the *current* source set is covered.
- Separate last partial and last full success timestamps, without overwriting
  FlareStore's installed-app/signing ledger or source metadata.

Run unit tests from `native/` with `swift test`.

## Work that **is not** integrated

This GitHub repository does **not** contain the publisher's Swift source
`BackgroundRefreshManager.swift` or `RepositoryViewModel.swift`.
The user-supplied original IPA contains compiled versions of those types,
and importing a Swift Package into this repository does not alter that IPA.
The existing injected Objective-C runtime is a **UI overlay** and cannot
safely substitute for the original async repository-fetch implementation.

To ship an **actual original FlareStorePlus IPA fix**, the native host must:

1. Extract the existing source-ID list in prioritised order, retaining signed
   bundle identity and existing repository-cache semantics.
2. Implement `SourceRefreshBackend.refreshSource(id:deadline:)` using the
   *host's existing single-repository fetch and cache-commit routine*.
   This adapter must honour both deadline and task cancellation.
3. Instantiate `CheckpointedBackgroundRefresher` with
   `JSONFileRefreshCheckpointStore` under the app's existing private
   Application Support directory. Do **not** use UserDefaults for a large
   source-response cache or change the existing source-list registration.
4. Replace only the work done inside the existing BGAppRefreshTask launch
   handler with one bounded batch, and call `setTaskCompleted(success:)`
   **exactly once**. `expirationHandler` should cancel the worker; next
   launch resumes from the atomic checkpoint. Schedule the next request
   once, respecting iOS discretion.
5. Resume unfinished batches on foreground opening, independently of any
   automatic install/signing operations. A failed/partial refresh must not
   claim "Last successful full refresh".
6. Test on physical iOS 27: 33 source rotation, forced expiration, slow
   URLs, first launch after upgrade, app/group ID preservation, and actual
   update badge correctness.

Do not hook arbitrary Swift async function pointers based on a string
reference alone. A safe function ABI/call site or original host source is
required for the original IPA integration. **No background-refresh-fix IPA
is released from this standalone module.**

Apple background refresh is discretionary; this engine improves partial
progress and recovery but cannot guarantee hourly execution or unattended
installation of sideloaded apps.
