#!/usr/bin/env bash
# Scaffold a throwaway Flutter macOS app that exercises the Data Protection
# keychain, ready to sign + run. Automates the mechanical steps of
# tool/dp_keychain_verification.md; you still do the one thing that can't be
# headless — set your signing Team in Xcode — then `flutter run -d macos`.
#
#   ./tool/setup_dp_verify.sh [dest-dir] [org]
#       dest-dir  where to create the app   (default: /tmp/dp_verify)
#       org       reverse-domain org prefix (default: ca.example)
#
# Needs Flutter + Xcode + an Apple Developer account.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${1:-/tmp/dp_verify}"
ORG="${2:-ca.example}"
BUNDLE="${ORG}.dpVerify"

rm -rf "$DEST"
flutter create --platforms=macos --org "$ORG" --project-name dp_verify "$DEST" >/dev/null
cd "$DEST"
rm -f test/widget_test.dart  # default counter-app test; we replace main.dart below

# 1. depend on this package (pub add edits the pubspec correctly + resolves)
flutter pub add secret_store --path "$REPO" >/dev/null

# 2. the probe (prints a grep-able result on launch, then exits)
cat > lib/main.dart <<EOF
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:secret_store/secret_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final r = await () async {
    try {
      final s = SecretStorage(
        service: '$BUNDLE.dptest',
        api: MacKeychainApi.dataProtection(),
      );
      await s.writeString('dp_key', 'dp-secret-value');
      final v = await s.readString('dp_key');
      await s.delete('dp_key');
      return 'SUCCESS: read back "\$v"';
    } on SecretStoreException catch (e) {
      return 'FAILED (\${e.code}): \${e.message}';
    }
  }();
  stdout.writeln('DP_RESULT_BEGIN\n\$r\nDP_RESULT_END');
  runApp(MaterialApp(home: Scaffold(body: Center(child: Text(r)))));
  await Future<void>.delayed(const Duration(seconds: 2));
  exit(0);
}
EOF

# 3. Keychain Sharing entitlement (implicit default access group — no value)
python3 - "$BUNDLE" <<'PY'
import sys, plistlib, pathlib
bundle = sys.argv[1]
for name in ("DebugProfile.entitlements", "Release.entitlements"):
    p = pathlib.Path("macos/Runner") / name
    d = plistlib.loads(p.read_bytes())
    d["keychain-access-groups"] = [f"$(AppIdentifierPrefix){bundle}"]
    p.write_bytes(plistlib.dumps(d))
    print(f"patched {p}")
PY

cat <<EOF

Scaffolded at: $DEST  (bundle id: $BUNDLE)

Next (the one non-headless step):
  1. open "$DEST/macos/Runner.xcworkspace"
  2. Runner target -> Signing & Capabilities -> Automatically manage signing -> pick your Team
  3. cd "$DEST" && flutter run -d macos      # watch for DP_RESULT_BEGIN ... DP_RESULT_END

Expected: SUCCESS: read back "dp-secret-value"
EOF
