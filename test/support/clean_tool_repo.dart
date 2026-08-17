import 'dart:io';

Future<Directory> stageCleanToolRepo(
  Directory temp,
  String sourceRoot,
  List<String> relativePaths,
) async {
  final repository = Directory('${temp.path}/tool-repo')..createSync();
  for (final relativePath in relativePaths) {
    final source = File('$sourceRoot/$relativePath');
    final destination = File('${repository.path}/$relativePath');
    destination.parent.createSync(recursive: true);
    source.copySync(destination.path);
  }
  await _git(repository, ['init', '--quiet']);
  await _git(repository, ['config', 'user.email', 'fixture@keybay.invalid']);
  await _git(repository, ['config', 'user.name', 'Keybay Test']);
  await _git(repository, ['config', 'commit.gpgsign', 'false']);
  await _git(repository, ['config', 'core.hooksPath', '/dev/null']);
  await _git(repository, ['add', '--all']);
  await _git(repository, ['commit', '--quiet', '-m', 'clean tool fixture']);
  return repository;
}

Future<void> _git(Directory repository, List<String> arguments) async {
  final result = await Process.run(
    '/usr/bin/git',
    ['-C', repository.path, ...arguments],
  );
  if (result.exitCode != 0) {
    throw StateError('git ${arguments.join(' ')} failed: ${result.stderr}');
  }
}
