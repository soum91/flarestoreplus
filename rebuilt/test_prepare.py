import json
from pathlib import Path
import tempfile
import unittest

from prepare import before_bootstrap, after_bootstrap


class BrandingTests(unittest.TestCase):
    def test_identity_and_three_component_base_version(self):
        with tempfile.TemporaryDirectory() as directory:
            engine = Path(directory)
            (engine / "upstream.lock.json").write_text(json.dumps({
                "bundle_identifier": "com.soum91.embersign", "version": "0.2.1",
            }))
            (engine / "project.yml").write_text("\n".join([
                "INFOPLIST_KEY_CFBundleDisplayName: EmberSign",
                "CFBundleDisplayName: EmberSign",
                "PRODUCT_BUNDLE_IDENTIFIER: com.soum91.embersign.widget",
                "group.com.soum91.embersign",
            ]))
            before_bootstrap(engine)
            data = json.loads((engine / "upstream.lock.json").read_text())
            project = (engine / "project.yml").read_text()
            self.assertEqual(data["bundle_identifier"], "com.soum91.flarestoreplus")
            self.assertEqual(data["version"], "0.1.0")
            self.assertIn("com.soum91.flarestoreplus.widget", project)
            self.assertIn("group.com.soum91.flarestoreplus", project)
            self.assertNotIn("group.com.soum91.embersign", project)

    def test_visible_export_and_unrelated_engine_code_unchanged(self):
        with tempfile.TemporaryDirectory() as directory:
            engine = Path(directory)
            tools = engine / "upstream/Feather/Ember/EmberToolsView.swift"
            tools.parent.mkdir(parents=True)
            original = ('Text("EmberSign").font(.title2.bold())\n'
                        '.navigationTitle("EmberSign")\n'
                        'let signingImplementationIsUntouched = true\n')
            tools.write_text(original)
            sources = engine / "upstream/Feather/Views/Sources/SourcesView.swift"
            sources.parent.mkdir(parents=True)
            sources.write_text(
                'import SwiftUI\n'
                'struct SourcesView {\n'
                '\t@State private var _searchText = ""\n'
                '\tvar body: some View {\n'
                '\t\tNBNavigationView("Sources") {\n'
                '\t\t\t.toolbar {\n'
                '\t\t\t\tNBToolbarButton(\n'
                '\t\t\t\t\tsystemImage: "plus"\n'
                '\t\t\t\t) {}\n'
                '\t\t\t}\n'
                '\t\t\t.sheet(isPresented: $_isAddingPresenting) {\n'
                '\t\t\t\tSourcesAddView()\n'
                '\t\t\t}\n'
                '\t\t}\n'
                '\t}\n'
                '}\n'
            )
            after_bootstrap(engine)
            updated = tools.read_text()
            self.assertIn('Text("FlareStorePlus").font(.title2.bold())', updated)
            self.assertIn('.navigationTitle("FlareStorePlus")', updated)
            self.assertIn("let signingImplementationIsUntouched = true", updated)
            ui = sources.read_text()
            self.assertIn('Label("Export Repositories", systemImage: "square.and.arrow.up")', ui)
            self.assertIn('accessibilityIdentifier("flarestoreplus.exportRepositories")', ui)
            self.assertIn('fileExporter(', ui)
            self.assertIn('EmberRepositoryListDocument(', ui)
            self.assertIn('Data from the original FlareStore is stored separately.', ui)


if __name__ == "__main__":
    unittest.main()
