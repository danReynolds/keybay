# Verifying the entitled macOS V2 profile

The supported path is:

```sh
KEYBAY_APPLE_TEAM_ID=<your-team-id> ./tool/test_e2e.sh macos-signed
```

It temporarily adds an Apple Development team and the exact
`keychain-access-groups` entitlement to `example_flutter`, provisions the host,
verifies the resulting code signature, runs
`integration_test/keybay_v2_macos_entitled_test.dart`, then runs the signed
seed/reopen continuity fixture as builds 101 and 102. It verifies each tested
app and restores the original configuration on exit. Verification
requires Apple-trusted signing, the expected
team and application identifier, the sole expected Keychain group, and sandboxing.
A configuration restoration failure fails the run and retains the backup.

The test exercises the complete V2 profile: signed application identity, one
Data Protection Keychain root in the exact signed group, an encrypted framed
file under Application Support, reopen, passphrase protection, and reset. It
does not infer Secure Enclave backing for a generic Keychain item.

## Prerequisites

- Xcode and an Apple Development identity.
- Automatic provisioning access for the selected team.
- Acceptance of the current Apple Developer Program agreement.

Use the team identifier from the provisioning profile or Xcode signing settings.
The suffix in an Apple Development certificate's display name may identify an
individual developer and must not be inferred to be the team.

## Isolated native file-Keychain qualification

```sh
./tool/test_macos_native.sh
```

This compiles a small test-only fixture with the installed Apple build tools,
creates a temporary Keychain with a fixed test password, and removes that
Keychain from the search list immediately. It verifies the existing search list
and default are unchanged and deletes its fixture on exit. No user item values
are read. The tests cover bounded root reads, lifecycle and passphrase changes,
reset, and a locked-keychain regression for prompt-free record operations.
Run in a native user session; an execution sandbox can report misleading
`OSStatus -50` errors or hide signing identities.

## Signed build continuity

The same `macos-signed` command runs
`integration_test/keybay_v2_macos_continuity_test.dart` in explicit `seed` and
`reopen` phases. It changes the build number from 101 to 102 and requires
different signed code-directory hashes, with the same exact application
identifier and sole Keychain group. Reopen must read the passphrase-protected
first build's value without initializing a store, then verify removal of the
provider root, encrypted store, and staging file after reset.

Each phase retains its JSON test events and verified signature metadata beside
the regression report. Missing, skipped, or failed test results cannot pass.
This demonstrates the tested Apple Development build replacement only; it does
not establish Developer ID release upgrades, entitlement transitions,
lock/reboot, or reinstall behavior.

If provisioning needs account authentication, open the workspace in Xcode once
and complete the account/2FA flow before rerunning the script.

## Manual equivalent

1. Add `DEVELOPMENT_TEAM` and `CODE_SIGN_IDENTITY = Apple Development` to
   `example_flutter/macos/Runner/Configs/AppInfo.xcconfig`.
2. Add the following to
   `example_flutter/macos/Runner/DebugProfile.entitlements`:

   ```xml
   <key>keychain-access-groups</key>
   <array>
     <string>$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)</string>
   </array>
   ```

3. Provision and run:

   ```sh
   cd example_flutter
   flutter build macos --debug --config-only
   cd macos
   xcodebuild build -workspace Runner.xcworkspace -scheme Runner \
     -configuration Debug -destination 'platform=macOS' \
     -allowProvisioningUpdates
   cd ..
   flutter test integration_test/keybay_v2_macos_entitled_test.dart -d macos
   ```

4. Restore both configuration files. The script does this automatically and is
   preferred because its exit trap also restores them after a failed run.
