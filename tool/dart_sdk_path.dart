import 'dart:io';

void main() =>
    stdout.writeln(File(Platform.resolvedExecutable).parent.parent.path);
