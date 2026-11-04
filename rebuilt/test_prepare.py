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

    def test_only_display_strings_change_after_bootstrap(self):
        with tempfile.TemporaryDirectory() as directory:
            engine = Path(directory)
            tools = engine / "upstream/Feather/Ember/EmberToolsView.swift"
            tools.parent.mkdir(parents=True)
            original = ('Text("EmberSign").font(.title2.bold())\n'
                        '.navigationTitle("EmberSign")\n'
                        'let signingImplementationIsUntouched = true\n')
            tools.write_text(original)
            after_bootstrap(engine)
            updated = tools.read_text()
            self.assertIn('Text("FlareStorePlus").font(.title2.bold())', updated)
            self.assertIn('.navigationTitle("FlareStorePlus")', updated)
            self.assertIn("let signingImplementationIsUntouched = true", updated)


if __name__ == "__main__":
    unittest.main()
