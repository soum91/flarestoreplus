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
    replace_all(
        tools,
        'Text("Version \\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")")',
        'Text("Installed version \\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown") (build \\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"))")',
    )

    expose_repository_export(engine / "upstream/Feather/Views/Sources/SourcesView.swift")

    # XcodeGen writes the app and widget entitlements from project.yml during
    # the later build step. Both were isolated in before_bootstrap().


def expose_repository_export(sources: Path) -> None:
    """Add a visible, native JSON export to the actual Sources toolbar."""
    replace_all(sources, "import SwiftUI\n", "import SwiftUI\nimport UniformTypeIdentifiers\n")
    replace_all(
        sources,
        '@State private var _searchText = ""',
        '@State private var _searchText = ""\n'
        '\t@State private var _isExportingRepositories = false\n'
        '\t@State private var _showEmptyRepositoryExportAlert = false',
    )
    replace_all(
        sources,
        '\t\t\t.toolbar {\n\t\t\t\tNBToolbarButton(',
        '\t\t\t.toolbar {\n'
        '\t\t\t\tToolbarItem(placement: .topBarTrailing) {\n'
        '\t\t\t\t\tButton {\n'
        '\t\t\t\t\t\tif _sources.isEmpty {\n'
        '\t\t\t\t\t\t\t_showEmptyRepositoryExportAlert = true\n'
        '\t\t\t\t\t\t} else {\n'
        '\t\t\t\t\t\t\t_isExportingRepositories = true\n'
        '\t\t\t\t\t\t}\n'
        '\t\t\t\t\t} label: {\n'
        '\t\t\t\t\t\tLabel("Export Repositories", systemImage: "square.and.arrow.up")\n'
        '\t\t\t\t\t}\n'
        '\t\t\t\t\t.accessibilityIdentifier("flarestoreplus.exportRepositories")\n'
        '\t\t\t\t}\n'
        '\t\t\t\tNBToolbarButton(',
    )
    replace_all(
        sources,
        '\t\t\t.sheet(isPresented: $_isAddingPresenting) {\n'
        '\t\t\t\tSourcesAddView()\n'
        '\t\t\t}',
        '\t\t\t.sheet(isPresented: $_isAddingPresenting) {\n'
        '\t\t\t\tSourcesAddView()\n'
        '\t\t\t}\n'
        '\t\t\t.fileExporter(\n'
        '\t\t\t\tisPresented: $_isExportingRepositories,\n'
        '\t\t\t\tdocument: EmberRepositoryListDocument(\n'
        '\t\t\t\t\turls: _sources.compactMap { $0.sourceURL?.absoluteString }\n'
        '\t\t\t\t),\n'
        '\t\t\t\tcontentType: .json,\n'
        '\t\t\t\tdefaultFilename: "flarestoreplus-repositories"\n'
        '\t\t\t) { result in\n'
        '\t\t\t\tif case .failure(let error) = result {\n'
        '\t\t\t\t\tUIAlertController.showAlertWithOk(\n'
        '\t\t\t\t\t\ttitle: "Export failed",\n'
        '\t\t\t\t\t\tmessage: error.localizedDescription\n'
        '\t\t\t\t\t)\n'
        '\t\t\t\t}\n'
        '\t\t\t}\n'
        '\t\t\t.alert("No repositories to export", isPresented: $_showEmptyRepositoryExportAlert) {\n'
        '\t\t\t\tButton("OK", role: .cancel) {}\n'
        '\t\t\t} message: {\n'
        '\t\t\t\tText("FlareStorePlus has no saved repositories yet. Data from the original FlareStore is stored separately.")\n'
        '\t\t\t}',
    )


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
