<!-- keybay-watcher-assessment: {"schema":1,"report_id":"github-32702923289-1","status":"assessed","summary":"Dependencies and platforms were quiet; 27 peer signals were reviewed with no applicable Keybay vulnerability or follow-up work identified.","actions":[]} -->

# Assessment

Status: **Assessed**

## Result

This complete run found no known vulnerability in the resolved dependency
graph and no new platform advisory in the watch window. All 27 peer activity
signals were compared with Keybay's current implementation, tests, and
security invariants. None identified an applicable Keybay vulnerability or
concrete follow-up work.

This is evidence that the configured sources ran and were triaged, not proof
that Keybay has no vulnerabilities.

## Dependencies

No finding. OSV checked every committed resolved lockfile and returned no
vulnerability. The reviewed cryptography release feed returned no new release
requiring investigation.

## Platforms

No finding. The Apple security-release, Android security-bulletin, and narrow
Linux credential-provider windows returned no new advisory for review.

## Peers

No finding after applicability review.

- The Android SDK and Gradle configuration-cache signals concern native plugin
  build configuration. Keybay is a pure Dart/FFI package and does not ship an
  Android Gradle plugin. The Gradle-wrapper updates are peer maintenance only.
- Android biometric, encrypted-SharedPreferences migration, plugin lifecycle,
  and React Native DataStore findings concern features and storage mechanisms
  Keybay does not implement. Keybay does not require per-use biometrics; its
  own Keystore path maps missing, unusable, or authentication-failed key
  material to typed failures instead of silently replacing it.
- The Apple accessibility-filter and cloud-sync findings remain structurally
  avoided: Keybay lookup queries do not include accessibility, and native
  items are fixed to `AfterFirstUnlockThisDeviceOnly` with synchronization
  disabled. Non-empty updates use `SecItemUpdate`; the sole zero-byte
  delete/re-add exception is documented, tested, and fails loudly if re-add
  does not succeed.
- The Linux schema-lifetime, content-type, and Python libsecret findings apply
  to direct native clients or Python keyring APIs. Keybay instead delegates to
  `secret-tool`, transports base64 text, and exercises that provider path in
  Linux CI. The SSH-agent backend proposal is not a Keybay dependency or
  provider.
- The remaining signals were peer-specific web behavior, Python CLI/backend
  semantics, dependency maintenance, or unspecific runtime reports with no
  shared Keybay mechanism or security-contract impact.

## Actions

None. No plausible Keybay vulnerability was found, so no public issue or
private advisory was opened. No unresolved provider-dependent claim remained,
so this run did not trigger physical-device qualification.
