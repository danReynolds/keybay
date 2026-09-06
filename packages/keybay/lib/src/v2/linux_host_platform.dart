/// Linux profile selection from confinement evidence, without provider fallback.
library;

import 'dart:io';

import 'flatpak_host_platform.dart';
import 'host_platform.dart';
import 'linux_desktop_host_platform.dart';
import 'platform_protector.dart';

final class LinuxHostPlatform implements HostPlatform {
  LinuxHostPlatform()
    : _isLinux = Platform.isLinux,
      _hasFlatpakMarker = currentProcessHasFlatpakMarker,
      _flatpak = FlatpakHostPlatform(),
      _desktop = LinuxDesktopHostPlatform();

  LinuxHostPlatform.test({
    required bool Function() hasFlatpakMarker,
    required HostPlatform flatpak,
    required HostPlatform desktop,
    bool isLinux = true,
  }) : _isLinux = isLinux,
       _hasFlatpakMarker = hasFlatpakMarker,
       _flatpak = flatpak,
       _desktop = desktop;

  final bool _isLinux;
  final bool Function() _hasFlatpakMarker;
  final HostPlatform _flatpak;
  final HostPlatform _desktop;

  @override
  Future<ResolvedHost> resolve() async {
    if (!_isLinux) {
      throw const PlatformProtectorFailure(
        PlatformProtectorFailureCode.unavailable,
      );
    }
    return (_hasFlatpakMarker() ? _flatpak : _desktop).resolve();
  }
}
