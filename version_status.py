"""Reference version/update decision logic for reverse-engineering tests.

Not yet integrated into FlareStore's compiled Swift binary.

An app may be re-signed under a different bundle ID, so a successful install
record needs both the repository identity and the actual installed identity.
Do not mark an update complete based only on tapping Install or staging an IPA.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
import re


class Decision(str, Enum):
    INSTALL = "install"
    UPDATE = "update"
    CURRENT = "current"
    UNKNOWN = "unknown"


@dataclass(frozen=True)
class InstalledApp:
    bundle_id: str
    version: str | None
    build: str | None = None


@dataclass(frozen=True)
class InstallRecord:
    original_bundle_id: str
    installed_bundle_id: str
    source_version: str
    source_build: str | None
    source_release_id: str | None
    confirmed: bool


def _parts(version: str | None) -> tuple[int, ...] | None:
    if not version or not re.fullmatch(r"\d+(?:\.\d+)*", version):
        return None
    return tuple(int(piece) for piece in version.split("."))


def _compare(a: str | None, b: str | None) -> int | None:
    left, right = _parts(a), _parts(b)
    if left is None or right is None:
        return None
    length = max(len(left), len(right))
    left += (0,) * (length - len(left))
    right += (0,) * (length - len(right))
    return (left > right) - (left < right)


def update_decision(
    original_bundle_id: str,
    latest_version: str,
    latest_build: str | None,
    installed: dict[str, InstalledApp],
    records: list[InstallRecord],
    latest_release_id: str | None = None,
) -> Decision:
    """Decide from confirmed, still-present installs; never trust stale ledger alone.

    The original source version stored by the ledger is preferred when signing
    transforms changed a binary's version. Without a confirmed match to the
    actual installed ID, the result is an ordinary Install action.
    """
    matches = [
        record for record in records
        if record.original_bundle_id == original_bundle_id
        and record.confirmed
        and record.installed_bundle_id in installed
    ]
    if not matches:
        return Decision.INSTALL
    # A device may hold several re-signed variants. Prefer the newest source
    # version; never rely on the ordering of persistence records.
    best = matches[0]
    for candidate in matches[1:]:
        result = _compare(candidate.source_version, best.source_version)
        if result is None:
            return Decision.UNKNOWN
        if result > 0:
            best = candidate
    if latest_release_id and best.source_release_id == latest_release_id:
        return Decision.CURRENT
    result = _compare(latest_version, best.source_version)
    if result is None:
        return Decision.UNKNOWN
    if result > 0:
        return Decision.UPDATE
    if result < 0:
        return Decision.CURRENT
    if latest_build and best.source_build:
        build_result = _compare(latest_build, best.source_build)
        if build_result is None:
            return Decision.UNKNOWN
        return Decision.UPDATE if build_result > 0 else Decision.CURRENT
    return Decision.CURRENT

