# FlareStorePlus source rebuild

This is a new, source-controlled sideloading app built on the GPLv3 EmberSign / Feather codebase. It is **not** a modified redistribution of the proprietary FlareStore IPA. Existing binary patch experiments in this repository are preserved separately.

The build uses a pinned EmberSign commit and only changes the new app's identity and presentation. It retains Apple Account provisioning, imported-certificate signing, native repository import/export, and the inherited paired-device tools. All installed-app and JIT functionality still requires real-device validation.

The independent app has bundle identifier `com.soum91.flarestoreplus` so it can be installed alongside FlareStore and EmberSign. Repository transfer exports a JSON list of URLs, never credentials or certificates. Batch import accepts the same JSON format, text lists and individual public GitHub feeds.

Versioning is `MAJOR.MINOR.BUILD` with an independent numeric `CFBundleVersion` / feed `buildVersion`. For example, the 98th build is `0.1.98`, not `0.1.0.98`. This avoids clients truncating the displayed version after the third component.

Private GitHub release downloads require authentication. Do not advertise an installable JSON source pointing to private release assets, which anonymous iOS sideloaders cannot fetch. The GitHub Actions artifact is available to the repository owner; sign the resulting IPA with your own certificate before installation.

The workflow publishes the complete rebuilt source and license texts alongside the IPA, preserving GPLv3 distribution requirements.
