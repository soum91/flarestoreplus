# Original FlareStore IPA: Background refresh binary integration audit

Date: 2026-11-11
Input: owner-provided FlareStorePlus 1.5.2 (63) IPA, `com.Flare.FlareStore-iOS`
Input binary: `Payload/FlareStore iOS.app/FlareStore iOS` (arm64, stripped Swift Mach-O)

## Verified data from binary analysis

The original executable defines the following Swift/ObjC runtime classes:

| Class | Instance size | ObjC base method list | Relevant stored ivars |
|---|---:|---|---|
| `_TtC14FlareStore_iOS24BackgroundRefreshManager` | 104 bytes | null | `savedURLsKey`, `widgetSuiteName`, `widgetAppsKey`, `widgetReposKey`, `widgetLastUpdateKey` |
| `_TtC14FlareStore_iOS19RepositoryViewModel` | 200 bytes | null | `_repositories`, `_savedURLs`, `_isRefreshing`, `urlSession`, `refreshTask`, `processingQueue`, `fetchBatchSize` |

Source-path identifiers embedded in the binary:
- `FlareStore_iOS/BackgroundRefreshManager.swift`
- `FlareStore_iOS/RepositoryViewModel.swift`

Literal log messages:
- `[RepoVM] fetchAllRepositoriesInternal: START fetching`
- `[RepoVM]   batch`
- `[RepoVM] fetchAllRepositoriesInternal: ALL DONE`
- `ended by iOS while fetching sources`

Runtime preferences and task identifiers:
- `savedRepositoryURLs`
- `repositoryCacheDate`
- `backgroundRefreshLastRun`
- `com.flarestore.background-refresh`

The original executable already has a batching mechanism, but the BG task still
works through all 33 sources. A last-successful-run screenshot shows ~19 seconds
for a full 33-source run, while 8/10 attempted runs were marked `ENDED BY iOS`.

## Why the standalone native implementation isn't yet wired into this IPA

The Swift BG fetcher classes have **no ObjC base methods**, so their private
async methods cannot be reliably intercepted using `method_exchangeImplementations`
or ordinary selector swizzling. The visible `fetchBatchSize` field does not
provide a verified public setter, nor do we know a stable way to obtain its
live object from this binary. Instance metadata describes stored fields, not
the Swift async calling conventions or call addresses necessary to replace a
method safely.

Direct patching of unverified Mach-O instruction offsets or rewriting the
`savedRepositoryURLs` preference during background tasks risks corrupting the
user's repository list, update cache, app signing/install state, and/or app
stability. A sidecar engine that merely downloads sources into a separate cache
would not update FlareStore's authoritative cache.

## Release gate

**Do not release a 'BG refresh fixed' IPA** until one of these is verified:

1. Original host source for `BackgroundRefreshManager.swift` and
   `RepositoryViewModel.swift`, then call the checkpointed library from
   the existing task handler and single-source cache commit; or
2. ABI-correct Swift binary hooking with a validated delegate/adapter, tested
   on a disposable app container / test device, with rollback and real device
   cancellation diagnostics.

Tests of the standalone native library passing in GitHub CI are NOT proof of
original-app integration. Keep the existing b63 published feed intact until
a working, signed, device-tested replacement exists.
