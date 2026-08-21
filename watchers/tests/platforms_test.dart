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
    expect(
      found.map((item) => item.marker),
      <String>['keybay-platform-android-2026-09-01'],
    );
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

  test('Linux deduplicates distro records by CVE', () async {
    final ubuntu = <String, Object?>{
      'id': 'UBUNTU-CVE-2026-12345',
      'published': '2026-09-01T00:00:00Z',
      'aliases': <Object?>['CVE-2026-12345'],
    };
    final debian = <String, Object?>{
      'id': 'DEBIAN-CVE-2026-12345',
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
        return <Map<String, Object?>>[
          ecosystem == 'Ubuntu' ? ubuntu : debian,
        ];
      },
    );
    expect(found, hasLength(1));
    expect(found.single.marker, 'keybay-platform-linux-CVE-2026-12345');
    expect(found.single.subjects, <String>[
      'Debian/gnome-keyring',
      'Ubuntu/gnome-keyring',
    ]);
  });
}
