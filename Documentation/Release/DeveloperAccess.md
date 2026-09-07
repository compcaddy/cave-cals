# Developer access testing

Developer Settings is available in Debug and TestFlight (sandbox receipt) builds.

- Empty DEV_API_TOKEN selects https://cavecals.vercel.app, ignoring stale localhost overrides.
- A nonempty DEV_API_TOKEN enables local development only. That credential is never sent to production.
- To test real production analysis, save the separately issued private test-access key in Developer Settings. It is stored in the device Keychain, not UserDefaults or the app bundle.
- Enable Override subscription for testing. Upgraded access ON grants real analysis; OFF forces free/paywall behavior. Disable the override to restore actual subscription checks.
- Overrides are included in the App Attest-signed request body. The server checks the credential against AI_TEST_ACCESS_KEY_SHA256 after normal device authentication, on every status/upload/analyze request. Invalid or revoked credentials fail closed. Existing quotas are unchanged.
- Rotate or remove AI_TEST_ACCESS_KEY_SHA256 and redeploy to revoke the capability. Anyone given the private key can use this testing permission on an attested device; do not distribute it to ordinary testers.

The owner key is stored outside this repository at ~/.codex/.tmp/cavecals-test-access-key.txt (mode 600). It is never included in documentation, tests, build artifacts, or source control.

Validation: 10 backend tests and TypeScript checks passed; 5 focused native tests passed. Production rejects unauthenticated override attempts. Real-device App Attest, key entry, and a complete live analysis with the toggle still need on-phone verification.

Build 4 adds one automatic re-registration attempt after Apple's invalidKey or the backend's unknown_device response, while holding the original request serialization gate. Other failures preserve the key and show Apple's error domain/code. Reset device verification in Developer Settings clears only the App Attest key reference, then checks access again; it preserves the saved test key, food diary, and preferences. Six focused native tests passed. The reported physical-phone failure has not yet been reproduced or confirmed resolved on device.
