#!/usr/bin/env python3
"""Identity-only customization of the pinned, independently rebuilt app."""

import argparse
import json
from pathlib import Path


APP_ID = "com.soum91.flarestoreplus"
APP_GROUP = "group.com.soum91.flarestoreplus"
BASE_VERSION = "0.1.0"


def replace_all(path: Path, previous: str, replacement: str) -> None:
    source = path.read_text(encoding="utf-8")
    if previous not in source:
        raise RuntimeError(f"Missing expected identity marker in {path}: {previous}")
    path.write_text(source.replace(previous, replacement), encoding="utf-8")


def before_bootstrap(engine: Path) -> None:
    lock = engine / "upstream.lock.json"
    data = json.loads(lock.read_text(encoding="utf-8"))
    data["bundle_identifier"] = APP_ID
    data["version"] = BASE_VERSION
    lock.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")

    project = engine / "project.yml"
    replace_all(project, "INFOPLIST_KEY_CFBundleDisplayName: EmberSign", "INFOPLIST_KEY_CFBundleDisplayName: FlareStorePlus")
    replace_all(project, "CFBundleDisplayName: EmberSign", "CFBundleDisplayName: FlareStorePlus")
    replace_all(project, "group.com.soum91.embersign", APP_GROUP)
    replace_all(project, "com.soum91.embersign.widget", APP_ID + ".widget")


def after_bootstrap(engine: Path) -> None:
    # Branding only. Avoid changes to signing engines, JIT, account storage,
    # pairing, and installation code.
    tools = engine / "upstream/Feather/Ember/EmberToolsView.swift"
    replace_all(tools, 'Text("EmberSign").font(.title2.bold())', 'Text("FlareStorePlus").font(.title2.bold())')
    replace_all(tools, '.navigationTitle("EmberSign")', '.navigationTitle("FlareStorePlus")')

    # XcodeGen writes the app and widget entitlements from project.yml during
    # the later build step. Both were isolated in before_bootstrap().


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("phase", choices=("before", "after"))
    parser.add_argument("engine", type=Path)
    args = parser.parse_args()
    engine = args.engine.resolve()
    if args.phase == "before":
        before_bootstrap(engine)
    else:
        after_bootstrap(engine)


if __name__ == "__main__":
    main()
