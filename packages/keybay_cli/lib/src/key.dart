const int cliKeyMaxLength = 120;

final RegExp _cliKeyPattern = RegExp(
  r'[A-Za-z0-9][A-Za-z0-9._-]*'
  r'(?:/[A-Za-z0-9][A-Za-z0-9._-]*)*',
);

/// Whether [key] is a key accepted by the Keybay CLI.
///
/// Matches the core library's key grammar:
/// one or more slash-separated segments, each beginning with an ASCII
/// alphanumeric character, and at most [cliKeyMaxLength] characters total.
bool isValidCliKey(String key) {
  if (key.isEmpty || key.length > cliKeyMaxLength) return false;

  final match = _cliKeyPattern.matchAsPrefix(key);
  return match != null && match.end == key.length;
}
