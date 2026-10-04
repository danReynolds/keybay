// No vault access, device discovery, PIN prompt or credential ceremony.
import 'dart:ffi';
import 'dart:io';

void main() {
  final name = Platform.isMacOS
      ? 'libkeypass_hardware.dylib'
      : 'libkeypass_hardware.so';
  final library = DynamicLibrary.open(
    '${File(Platform.resolvedExecutable).parent.path}/$name',
  );
  final version = library.lookupFunction<Uint32 Function(), int Function()>(
    'keypass_hardware_abi_version',
  )();
  if (version != 1) throw StateError('Unsupported hardware ABI');
  stdout.writeln('Hardware ABI $version loaded. No device accessed.');
}
