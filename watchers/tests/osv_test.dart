import 'package:test/test.dart';

import '../osv.dart';

void main() {
  test('OSV client paginates and validates IDs', () async {
    final responses = <Object?>[
      <String, Object?>{
        'vulns': <Object?>[
          <String, Object?>{'id': 'ONE-1'},
        ],
        'next_page_token': 'next',
      },
      <String, Object?>{
        'vulns': <Object?>[
          <String, Object?>{'id': 'TWO-2'},
        ],
      },
    ];
    var index = 0;

    final found = await queryPackage(
      'Pub',
      'example',
      post: (body) async {
        if (index == 1) {
          expect(body['page_token'], 'next');
        }
        return responses[index++];
      },
    );

    expect(found.map((item) => item['id']), <String>['ONE-1', 'TWO-2']);
  });

  test('OSV client rejects unsafe advisory IDs', () async {
    await expectLater(
      queryPackage(
        'Pub',
        'example',
        post: (_) async => <String, Object?>{
          'vulns': <Object?>[
            <String, Object?>{'id': 'bad id'},
          ],
        },
      ),
      throwsFormatException,
    );
  });
}
