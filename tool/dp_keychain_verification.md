# Verifying the macOS Data Protection keychain (manual)

`MacKeychainApi.dataProtection()` targets the DP keychain (AES-256-GCM + Secure
Enclave). Its **refusal** path is covered automatically in CI
(`keychain_integration_test.dart` asserts an unentitled process gets
`errSecMissingEntitlement` −34018 → `KeystoreUnreachable`). Its **success** path
cannot be CI-tested: DP requires a code-signed app bundle carrying a
`keychain-access-groups` entitlement authorized by a **provisioning profile**,
and CI can neither sign nor provision. This is that manual check — run it when
the DP binding, the entitlement handling, or the macOS SDK changes.

Verified facts (so you know what "working" looks like at each step):

- Unsigned CLI → −34018 → typed `KeystoreUnreachable`. ✓ (also in CI)
- Locally-signed **bare binary** with the entitlement → **SIGKILL** (AMFI
  rejects a restricted entitlement with no profile). ✓ — proves a bundle +
  profile is required, not just a signature.
- Signed, provisioned **app bundle** → store/read/delete succeeds. ← this doc.

## Procedure (~5 min, needs Xcode + an Apple Developer account)

**Fast path:** `./tool/setup_dp_verify.sh [dest] [org]` automates steps 1–3
(scaffolds the app, injects the probe, adds the entitlement). Then do steps
4–5. The manual steps below document what the script does, for when you want to
understand or adjust it.

1. Create a throwaway Flutter macOS app and add this package as a path dep:

   ```sh
   flutter create --platforms=macos --org ca.example dp_verify
   cd dp_verify
   # pubspec.yaml → dependencies:  secret_store: { path: /abs/path/to/secret_store }
   flutter pub get
   ```

2. Replace `lib/main.dart` with the probe (prints a grep-able result, then exits):

   ```dart
   import 'dart:io';
   import 'package:flutter/material.dart';
   import 'package:secret_store/secret_store.dart';

   Future<void> main() async {
     WidgetsFlutterBinding.ensureInitialized();
     final r = await () async {
       try {
         final s = SecretStorage(
           service: 'ca.example.dpVerify.dptest',
           api: MacKeychainApi.dataProtection(),
         );
         await s.writeString('dp_key', 'dp-secret-value');
         final v = await s.readString('dp_key');
         await s.delete('dp_key');
         return 'SUCCESS: read back "$v"';
       } on SecretStoreException catch (e) {
         return 'FAILED (${e.code}): ${e.message}';
       }
     }();
     stdout.writeln('DP_RESULT_BEGIN\n$r\nDP_RESULT_END');
     runApp(MaterialApp(home: Scaffold(body: Center(child: Text(r)))));
     await Future<void>.delayed(const Duration(seconds: 2));
     exit(0);
   }
   ```

3. Add the Keychain Sharing entitlement to `macos/Runner/DebugProfile.entitlements`
   (and `Release.entitlements`). The default access group is implicit — no group
   value to configure:

   ```xml
   <key>keychain-access-groups</key>
   <array>
     <string>$(AppIdentifierPrefix)ca.example.dpVerify</string>
   </array>
   ```

4. Set signing: open `macos/Runner.xcworkspace` in Xcode → **Runner** target →
   **Signing & Capabilities** → check **Automatically manage signing** → pick
   your **Team**. Xcode authenticates (Apple ID, possibly 2FA) and generates the
   provisioning profile. *(This step is why it can't be headless — automatic
   provisioning needs an interactive account session.)*

5. Run and read the console:

   ```sh
   flutter run -d macos    # watch for the DP_RESULT_BEGIN … DP_RESULT_END block
   ```

   Expected: `SUCCESS: read back "dp-secret-value"`. A `FAILED (keystore_unreachable)`
   means the entitlement/profile isn't in effect — recheck steps 3–4.
