# Binary integration boundary

The native InstallAftercareBridge adds host-facing entry points for the Install/Update button, foreground installed-app reconciliation, and a verified installation_proxy callback. The bridge is compiled Swift source in this repository, NOT an injected hook in the supplied third-party b57 IPA.

Inspection of the user-supplied b57 Mach-O found the Swift-native types UpdateManager, InstallAftercare, InstalledAppsCache and InstallLedger, but not stable callable action-method symbols or safe Objective-C install-completion selectors. The main symbol table contains no app-internal Swift methods suitable for direct binding.

To finish the original request, the real host must call the bridge from the original SwiftUI actions, supply InstalledAppQuery using actual device installation metadata, supply InstallTransport, and refresh the Update UI from confirmed receipts. Linking an arbitrary module into a binary without knowing the method ABI and call graph is unsafe.

The test for same-build OTA reinstall specifically rejects falsely recording the pre-existing copy as a successful update. Only authoritative installation-proxy completion can confirm such a transaction.

Do not claim that the built Swift module fixes the current b57 executable; do not publish b58 or alter the Google Drive feed based only on passing source tests.
