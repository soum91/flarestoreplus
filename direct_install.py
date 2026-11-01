"""Tested direct-install workflow contract, not yet wired into the iOS binary.

FlareStore already embeds installation_proxy, AFC PublicStaging, and a pairing
tunnel. This reference workflow specifies the behavior the Update button
needs, and deliberately has no web-manifest fallback or premature ledger write.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class SignedPackage:
    ipa_path: str
    original_bundle_id: str
    installed_bundle_id: str
    version: str
    build: str
    team_id: str | None
    source_release_id: str | None = None


@dataclass(frozen=True)
class DeviceApp:
    bundle_id: str
    version: str
    build: str
    team_id: str | None


class DirectInstallBackend(Protocol):
    async def ensure_paired_tunnel(self) -> None: ...

    async def installed_app(self, bundle_id: str) -> DeviceApp | None: ...

    async def stage_via_afc(self, ipa_path: str) -> str: ...

    async def install_via_proxy(self, staged_path: str) -> None: ...

    async def wait_for_install_completion(self, bundle_id: str) -> None: ...


class ConfirmedInstallLedger(Protocol):
    def record_completed(self, package: SignedPackage) -> None: ...


class InstallationRejected(Exception):
    pass


async def install_and_confirm(
    package: SignedPackage,
    backend: DirectInstallBackend,
    ledger: ConfirmedInstallLedger,
) -> DeviceApp:
    """Do not report success or clear Update until the device confirms the copy.

    Never delete an old app signed by a different team automatically: that can
    lose user data. Never fall back to web-manifest installation silently.
    """
    if not package.ipa_path or not package.installed_bundle_id:
        raise ValueError("Signed IPA path and actual installed bundle ID are required")
    await backend.ensure_paired_tunnel()
    existing = await backend.installed_app(package.installed_bundle_id)
    if existing and existing.team_id and package.team_id and existing.team_id != package.team_id:
        raise InstallationRejected(
            "Different signing team; direct overwrite may fail. Preserve the installed app and its data."
        )
    staged_path = await backend.stage_via_afc(package.ipa_path)
    if not staged_path.startswith("PublicStaging/"):
        raise InstallationRejected("Staged package path must be within AFC PublicStaging")
    await backend.install_via_proxy(staged_path)
    await backend.wait_for_install_completion(package.installed_bundle_id)
    observed = await backend.installed_app(package.installed_bundle_id)
    if observed is None:
        raise InstallationRejected("Installation claimed completion, but the app is not installed")
    if observed.version != package.version or observed.build != package.build:
        raise InstallationRejected("Installed version/build does not match the signed package")
    ledger.record_completed(package)
    return observed

