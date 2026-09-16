import 'package:keybay_cli/src/key.dart';
import 'package:test/test.dart';

void main() {
  group('CLI key grammar', () {
    test('accepts simple names and namespaced keys', () {
      expect(isValidCliKey('x'), isTrue);
      expect(isValidCliKey('openai-api-key'), isTrue);
      expect(isValidCliKey('acme-payments/openai-api-key'), isTrue);
      expect(isValidCliKey('acme_shared/service.key_2'), isTrue);
      expect(isValidCliKey('acme/project/staging/database-url'), isTrue);
      expect(isValidCliKey('0/1'), isTrue);
    });

    test('rejects empty and malformed keys', () {
      for (final key in <String>[
        '',
        '-key',
        'key with space',
        'key\n',
        '/key',
        'namespace/',
        '-namespace/key',
        'namespace/-key',
        'namespace//key',
        'namespace/key with space',
        'namespace/key\n',
        'kb://namespace/key',
      ]) {
        expect(isValidCliKey(key), isFalse, reason: 'accepted "$key"');
      }
    });

    test('enforces the complete-key length cap', () {
      final accepted = 'a/${'b' * (cliKeyMaxLength - 2)}';
      expect(accepted.length, cliKeyMaxLength);
      expect(isValidCliKey(accepted), isTrue);
      expect(isValidCliKey('${accepted}b'), isFalse);
    });
  });
}
