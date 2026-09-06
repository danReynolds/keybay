@Tags(<String>['unit'])
library;

import 'package:keybay/src/v2/application_identity.dart';
import 'package:keybay/src/v2/host_binding.dart';
import 'package:test/test.dart';

void main() {
  test(
    'container domain survives relocation but isolates identity and profile',
    () {
      final baseline = _binding();
      expect(
        baseline.domain.commitment,
        'S08sqEG6bIta-yQ1icUV0i5Cr9mVYoICL9fVZdkd9Ac',
      );
      final moved = _binding(
        physicalRoot: '/container-after/Library/Application Support/keybay-v2/',
      );
      expect(moved.canonicalFileRoot, isNot(baseline.canonicalFileRoot));
      expect(moved.domain, baseline.domain);
      expect(moved.providerAddress, baseline.providerAddress);
      expect(
        _binding(id: 'ABCDE12345.dev.keybay.other').domain,
        isNot(baseline.domain),
      );
      expect(
        _binding(id: 'ABCDE12345.dev.keybay.other').providerAddress,
        isNot(baseline.providerAddress),
      );
      expect(
        _binding(profile: 'macos.entitled.data-protection-file.v1').domain,
        isNot(baseline.domain),
      );
      expect(
        _binding(
          profile: 'macos.entitled.data-protection-file.v1',
        ).providerAddress,
        isNot(baseline.providerAddress),
      );
      expect(
        _binding(assurance: ApplicationIdentityAssurance.namespaceOnly).domain,
        isNot(baseline.domain),
      );
      expect(
        _binding(
          relativeRoot: 'Library/Application%20Support/other-store/',
        ).domain,
        isNot(baseline.domain),
      );
      final pathBound = ResolvedApplicationBinding.derive(
        identity: baseline.identity,
        profile: baseline.profile,
        canonicalFileRoot: baseline.canonicalFileRoot,
      );
      expect(pathBound.domain, isNot(baseline.domain));
      expect(pathBound.providerAddress, baseline.providerAddress);
    },
  );

  test('container location must be a fixed normalized relative directory', () {
    for (final invalid in [
      '',
      '/',
      '/Library/keybay-v2/',
      'file:///Library/keybay-v2/',
      '//host/Library/keybay-v2/',
      '../keybay-v2/',
      'Library/../../keybay-v2/',
      'Library/%2fother/keybay-v2/',
      'Library/%5cother/keybay-v2/',
      'Library/%00/keybay-v2/',
      'Library//keybay-v2/',
      'Library/keybay-v2',
      'Library/keybay-v2/?query',
      'Library/keybay-v2/#fragment',
    ]) {
      expect(
        () => _binding(relativeRoot: invalid),
        throwsArgumentError,
        reason: invalid,
      );
    }
  });
}

ResolvedApplicationBinding _binding({
  String id = 'ABCDE12345.dev.keybay.ios-test',
  String profile = 'ios.signed.data-protection-file.v1',
  String physicalRoot =
      '/container-before/Library/Application Support/keybay-v2/',
  String relativeRoot = 'Library/Application%20Support/keybay-v2/',
  ApplicationIdentityAssurance assurance =
      ApplicationIdentityAssurance.osEnforced,
}) => ResolvedApplicationBinding.forApplicationContainer(
  identity: ApplicationIdentity(
    stableValue: id,
    source: ApplicationIdentitySource.operatingSystem,
    assurance: assurance,
  ),
  profile: HostProfile(profile),
  canonicalFileRoot: Uri.directory(physicalRoot),
  containerRelativeRoot: Uri.parse(relativeRoot),
);
