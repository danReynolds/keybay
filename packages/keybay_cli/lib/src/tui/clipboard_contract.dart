import 'package:fleury/fleury_core.dart';

/// Never retain selected field text in the framework's clipboard register.
final class DiscardClipboard extends InProcessClipboard {
  @override
  String? readInProcess() => null;

  @override
  Future<ClipboardWriteReport> writeWithReport(
    String text, {
    ClipboardWritePolicy policy = ClipboardWritePolicy.standard,
  }) => super.writeWithReport('', policy: ClipboardWritePolicy.inProcessOnly);
}

final class TuiCopyException implements Exception {
  const TuiCopyException();
}
