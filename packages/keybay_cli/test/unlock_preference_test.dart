@Tags(['unit'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:keybay_cli/src/unlock_preference_file.dart';
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late File file;
  late FileUnlockPreference preference;
  const first = '0123456789abcdef0123456789abcdef';
  const second = 'abcdef0123456789abcdef0123456789';
  setUp(() {
    directory = Directory.systemTemp.createTempSync('keybay-preference-');
    file = File('${directory.path}/ui/unlock-method.json');
    preference = FileUnlockPreference(file);
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test(
    'persists only the method ID across instances and replaces atomically',
    () async {
      expect(await preference.read(), isNull);
      await preference.write(first);
      expect(await FileUnlockPreference(file).read(), first);
      expect(jsonDecode(file.readAsStringSync()), {
        'version': 1,
        'methodId': first,
      });
      await preference.write(second);
      expect(await preference.read(), second);
      expect(file.parent.listSync().map((e) => e.path), [file.path]);
    },
  );

  test(
    'malformed, oversized and unsupported data never becomes a method',
    () async {
      file.parent.createSync();
      for (final value in [
        '{',
        'null',
        '[]',
        'x' * 257,
        jsonEncode({'version': 2, 'methodId': first}),
        jsonEncode({'version': 1, 'methodId': '../another-store'}),
        jsonEncode({'version': 1, 'methodId': 42}),
      ]) {
        file.writeAsStringSync(value);
        expect(await preference.read(), isNull);
      }
      file.deleteSync();
      await preference.write('not-a-method-or-secret');
      expect(file.existsSync(), isFalse);
    },
  );

  test('non-file targets and unavailable directories are harmless', () async {
    file.parent.createSync();
    Directory(file.path).createSync();
    expect(await preference.read(), isNull);
    await preference.write(first);
    expect(Directory(file.path).existsSync(), isTrue);
    Directory(file.path).deleteSync();
    file.parent.deleteSync();
    File(file.parent.path).writeAsStringSync('unrelated');
    await preference.write(first);
    expect(await preference.read(), isNull);
    expect(File(file.parent.path).readAsStringSync(), 'unrelated');
  });

  test(
    'does not read or write through a preference symlink',
    () async {
      file.parent.createSync();
      final target = File('${directory.path}/unrelated')
        ..writeAsStringSync('retained');
      Link(file.path).createSync(target.path);
      expect(await preference.read(), isNull);
      await preference.write(first);
      expect(target.readAsStringSync(), 'retained');
      expect(Link(file.path).existsSync(), isTrue);
    },
    skip: Platform.isWindows,
  );
}
