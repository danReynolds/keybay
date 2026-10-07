import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../platforms/watcher.dart';

final start = DateTime.utc(2026, 8, 21);

void main() {
  test('Apple groups supported releases by date', () {
    const source = '''
      <table><tr><td><a href="https://support.apple.com/en-us/123456">iOS 27.0</a></td><td>iPhone</td><td>01 Sep 2026</td></tr>
      <tr><td><a href="https://support.apple.com/en-us/123457">macOS 27.0</a></td><td>Mac</td><td>01 Sep 2026</td></tr>
      <tr><td><a href="https://support.apple.com/en-us/123458">watchOS 27.0</a></td><td>Watch</td><td>01 Sep 2026</td></tr></table>
    ''';
    final found = appleFindings(
      source,
      startedAt: start,
      products: const <String>[
        'iOS',
        'iPadOS',
        'macOS',
        'Background Security Improvements',
      ],
    );
    expect(found, hasLength(1));
    expect(found.single.subjects, <String>['iOS 27.0', 'macOS 27.0']);
  });

  test('Apple rejects a table with no supported product rows', () {
    const source = '''
      <table><tr><td><a href="https://support.apple.com/en-us/123456">watchOS 27.0</a></td><td>Watch</td><td>01 Sep 2026</td></tr></table>
    ''';

    expect(
      () => appleFindings(
        source,
        startedAt: start,
        products: const <String>['iOS', 'iPadOS', 'macOS'],
      ),
      throwsFormatException,
    );
  });

  test('Android finds only new bulletins', () {
    const source = '''
      <a href="/docs/security/bulletin/2026-08-01">August</a>
      <a href="/docs/security/bulletin/2026-09-01">September</a>
    ''';
    final found = androidFindings(
      source,
      indexUri: Uri.parse('https://source.android.com/docs/security/bulletin'),
      startedAt: start,
    );
    expect(found.map((item) => item.marker), <String>[
      'keybay-platform-android-2026-09-01',
    ]);
  });

  test('Android rejects normalized invalid bulletin dates', () {
    expect(
      () => androidFindings(
        '<a href="/docs/security/bulletin/2026-02-31">Invalid</a>',
        indexUri: Uri.parse(
          'https://source.android.com/docs/security/bulletin',
        ),
        startedAt: start,
      ),
      throwsFormatException,
    );
  });

  test('Android category landing page fails rather than reporting quiet', () {
    expect(
      () => androidFindings(
        '<a href="/docs/security/bulletin/asb-overview">Bulletins Overview</a>',
        indexUri: Uri.parse(
          'https://source.android.com/docs/security/bulletin',
        ),
        startedAt: start,
      ),
      throwsFormatException,
    );
  });

  test(
    'configured Android overview discovers only official dated bulletins',
    () async {
      final config =
          jsonDecode(File('watchers/platforms/config.json').readAsStringSync())
              as Map<String, Object?>;
      final requested = <Uri>[];
      final found = await platformFindings(
        config,
        fetch: (uri) async {
          requested.add(uri);
          if (uri.host == 'support.apple.com') {
            return '<table><tr><td>iOS 26.0</td><td>iPhone</td>'
                '<td>01 Aug 2026</td></tr></table>';
          }
          expect(
            uri.toString(),
            'https://source.android.com/docs/security/bulletin/asb-overview',
          );
          return '''
          <a href="/docs/security/bulletin/2026-08-01">Old</a>
          <a href="/docs/security/bulletin/2026/2026-10-01">October</a>
          <a href="https://source.android.com/docs/security/bulletin/2026-10-01?hl=en">Duplicate</a>
          <a href="https://example.com/docs/security/bulletin/2026-11-01">Foreign host</a>
          <a href="http://source.android.com/docs/security/bulletin/2026-11-01">Insecure</a>
          <a href="/docs/security/bulletin/pixel/2026-11-01">Different source</a>
        ''';
        },
        query: (_, _) async => <Map<String, Object?>>[],
      );
      expect(requested, hasLength(2));
      expect(found.map((item) => item.marker), <String>[
        'keybay-platform-android-2026-10-01',
      ]);
      expect(
        found.single.references.single.url,
        'https://source.android.com/docs/security/bulletin/2026/2026-10-01',
      );
    },
  );

  test('Android rejects mismatched directory years', () {
    expect(
      () => androidFindings(
        '<a href="/docs/security/bulletin/2025/2026-10-01">Invalid</a>',
        indexUri: Uri.parse(
          'https://source.android.com/docs/security/bulletin/asb-overview',
        ),
        startedAt: start,
      ),
      throwsFormatException,
    );
  });

  test('Linux deduplicates distro records by CVE', () async {
    final ubuntu = <String, Object?>{
      'id': 'UBUNTU-CVE-2026-12345',
      'published': '2026-09-01T00:00:00Z',
      'aliases': <Object?>['CVE-2026-12345'],
    };
    final debian = <String, Object?>{
      'id': 'DEBIAN-CVE-2026-12345',
      'published': '2026-09-01T00:00:00Z',
      'modified': '2026-09-02T00:00:00Z',
      'aliases': <Object?>['CVE-2026-12345'],
    };
    final found = await linuxFindings(
      startedAt: start,
      ecosystems: const <String>['Ubuntu', 'Debian'],
      packages: const <String>['gnome-keyring'],
      query: (ecosystem, package) async {
        if (package != 'gnome-keyring') {
          return <Map<String, Object?>>[];
        }
        return <Map<String, Object?>>[ecosystem == 'Ubuntu' ? ubuntu : debian];
      },
    );
    expect(found, hasLength(1));
    expect(found.single.marker, 'keybay-platform-linux-CVE-2026-12345');
    expect(found.single.subjects, <String>[
      'Debian/gnome-keyring',
      'Ubuntu/gnome-keyring',
    ]);
  });

  test('Linux does not treat edits to old records as new advisories', () async {
    final found = await linuxFindings(
      startedAt: start,
      ecosystems: const <String>['Debian'],
      packages: const <String>['dbus'],
      query: (ecosystem, package) async => <Map<String, Object?>>[
        <String, Object?>{
          'id': 'DEBIAN-CVE-2014-3477',
          'published': '2014-07-01T00:00:00Z',
          'modified': '2026-09-01T00:00:00Z',
          'aliases': <Object?>['CVE-2014-3477'],
        },
      ],
    );

    expect(found, isEmpty);
  });

  test('platform backfill is bounded before ongoing monitoring', () async {
    final found = await platformBackfillFindings(
      <String, Object?>{
        'backfill_started_at': '2025-08-21T00:00:00Z',
        'started_at': '2026-08-21T00:00:00Z',
        'apple': <String, Object?>{
          'index': 'https://support.apple.com/en-us/100100',
          'products': <String>['iOS'],
        },
        'android': <String, Object?>{
          'index':
              'https://source.android.com/docs/security/bulletin/asb-overview',
        },
        'linux': <String, Object?>{
          'ecosystems': <String>['Ubuntu'],
          'packages': <String>['libsecret'],
        },
      },
      fetch: (uri) async {
        if (uri.host == 'support.apple.com') {
          return '''
            <table>
              <tr><td><a href="https://support.apple.com/en-us/123455">iOS 25.9</a></td><td>iPhone</td><td>20 Aug 2025</td></tr>
              <tr><td><a href="https://support.apple.com/en-us/123456">iOS 26.0</a></td><td>iPhone</td><td>21 Aug 2025</td></tr>
              <tr><td><a href="https://support.apple.com/en-us/123457">iOS 27.0</a></td><td>iPhone</td><td>21 Aug 2026</td></tr>
            </table>
          ''';
        }
        return '''
          <a href="/docs/security/bulletin/2025-08-20">Before</a>
          <a href="/docs/security/bulletin/2025-08-21">Included</a>
          <a href="/docs/security/bulletin/2026-08-21">Ongoing</a>
        ''';
      },
      query: (ecosystem, package) async => <Map<String, Object?>>[
        <String, Object?>{
          'id': 'UBUNTU-CVE-2025-12345',
          'published': '2025-08-21T00:00:00Z',
          'aliases': <Object?>['CVE-2025-12345'],
        },
        <String, Object?>{
          'id': 'UBUNTU-CVE-2026-12345',
          'published': '2026-08-21T00:00:00Z',
          'aliases': <Object?>['CVE-2026-12345'],
        },
      ],
    );

    expect(found, hasLength(3));
    final markers = found.map((item) => item.marker).toList();
    expect(
      markers.where(
        (marker) => marker.startsWith('keybay-platform-apple-2025-08-21-'),
      ),
      hasLength(1),
    );
    expect(markers, contains('keybay-platform-android-2025-08-21'));
    expect(markers, contains('keybay-platform-linux-CVE-2025-12345'));
  });

  test('platform backfill requires a non-empty earlier window', () {
    expect(
      () => platformBackfillFindings(<String, Object?>{
        'backfill_started_at': '2026-08-21T00:00:00Z',
        'started_at': '2026-08-21T00:00:00Z',
      }),
      throwsFormatException,
    );
  });
}
