"""Summarize FlareStore OTA install logs without equating downloads with installs.

Independent diagnostic tooling, not integrated into the iOS executable.
Only app names and event flags are retained, not paths or device IDs.
"""

from __future__ import annotations

from dataclasses import dataclass
import re


_TRANSFER = re.compile(r"Delivered [^\r\n]*?\.ipa to [^\r\n]*?: (\d+) of (\d+) bytes")
_APP = re.compile(r"\bApp: ([^,\r\n]+), ")
_UPDATED = re.compile(r"\b(.+?) updated in place \(was ")


@dataclass
class OtaAttempt:
    app_name: str | None = None
    manifest_ok: bool = False
    os_handoff: bool = False
    ipa_delivered: bool = False
    app_reported_update: bool = False

    @property
    def status(self) -> str:
        if self.app_reported_update:
            return "app_reported_update"
        if self.ipa_delivered:
            return "delivered_not_confirmed"
        if self.os_handoff:
            return "handoff_not_confirmed"
        if self.manifest_ok:
            return "preflight_only"
        return "started"


def summarize_ota_attempts(log: str) -> list[OtaAttempt]:
    attempts: list[OtaAttempt] = []
    attempt: OtaAttempt | None = None
    for line in log.splitlines():
        if "INFO  INSTALL " not in line:
            continue
        event = line.split("INFO  INSTALL ", 1)[1]
        if "───── Local install ─────" in event:
            attempt = OtaAttempt()
            attempts.append(attempt)
            continue
        if attempt is None:
            continue
        match = _APP.search(event)
        if match and attempt.app_name is None:
            attempt.app_name = match.group(1)
        if "Manifest fetch: HTTP 200" in event:
            attempt.manifest_ok = True
        if "Handed off to iOS" in event:
            attempt.os_handoff = True
        transfer = _TRANSFER.search(event)
        if transfer and int(transfer.group(1)) == int(transfer.group(2)) > 0:
            attempt.ipa_delivered = True
        updated = _UPDATED.search(event)
        if updated and attempt.app_name == updated.group(1):
            attempt.app_reported_update = True
    return attempts
