// A provider may keep its output descriptor open after cancellation. This
// process must exit naturally after the portal fails, without forcing exit().
import 'dart:io';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:dbus/dbus.dart';
import 'package:keybay/src/v2/linux_secret_portal.dart';
import 'package:keybay/src/v2/platform_protector.dart';

Future<void> main() async {
  final connection = _RetainingProvider();
  try {
    await DbusLinuxSecretPortal(
      timeout: const Duration(milliseconds: 50),
      clientFactory: () => connection,
    ).retrieveSecret(interaction: PlatformInteraction.allowed);
    throw StateError('Unexpected success');
  } on PlatformProtectorFailure catch (error) {
    if (error.code != PlatformProtectorFailureCode.operationFailed) rethrow;
    stdout.writeln('cancelled');
  }
  // Deliberately retain the provider's copy. Open, idle descriptors themselves
  // do not keep Dart alive; a pending blocking native read does.
}

final class _RetainingProvider implements LinuxSecretPortalConnection {
  int? retained;
  DBusObjectPath? path;

  @override
  String get uniqueName => ':1.25';
  @override
  Future<String?> resolveOwner({required bool activate}) async => ':1.40';
  @override
  Future<void> subscribeResponse({
    required DBusObjectPath path,
    required void Function(DBusSignal) onResponse,
    required void Function() onError,
  }) async {
    this.path = path;
  }

  @override
  Future<DBusMethodSuccessResponse> retrieve({
    required String owner,
    required String handleToken,
    required RandomAccessFile output,
  }) async {
    // SCM_RIGHTS carries native descriptor integers. Duplicate the sender's
    // descriptor as recvmsg would; converting its ResourceHandle directly
    // would create a second owner of the same descriptor rather than a copy.
    final rights = SocketControlMessage.fromHandles([
      ResourceHandle.fromFile(output),
    ]).data;
    if (rights.length != 4) throw StateError('Unexpected descriptor message');
    final fd = ByteData.sublistView(rights).getInt32(0, Endian.host);
    retained = DynamicLibrary.process()
        .lookupFunction<Int32 Function(Int32), int Function(int)>('dup')(fd);
    if (retained! < 0) throw StateError('Descriptor duplication failed');
    return DBusMethodSuccessResponse([path!]);
  }

  @override
  Future<void> closeRequest({
    required String owner,
    required DBusObjectPath path,
  }) async {}
  @override
  Future<void> close() async {}
}
