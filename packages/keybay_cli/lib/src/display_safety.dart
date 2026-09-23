/// Code points that never reach the terminal as themselves when Keybay shows a
/// stored value: C0 and C1 controls (except LF, which is layout), DEL, line and
/// paragraph separators, lone surrogates, and every Unicode format character or
/// other default-ignorable code point. Each can drive the terminal or make the
/// display disagree with the stored bytes: bidi overrides and isolates,
/// joiners and zero-width marks, prepended concatenation marks that fold the
/// next character into an unpainted cluster, tag characters and fillers.
///
/// Variation selectors stay unescaped so emoji and CJK variants render.
/// Everything else printable (accents, CJK, emoji) renders as itself.
bool mustEscapeRune(int rune) =>
    rune < 0x20 && rune != 0x0a ||
    rune >= 0x7f && rune <= 0x9f ||
    rune == 0x2028 ||
    rune == 0x2029 ||
    rune >= 0xd800 && rune <= 0xdfff ||
    _isInvisibleFormat(rune);

bool _isInvisibleFormat(int rune) {
  if (rune < 0xad) return false;
  for (final (start, end) in _invisibleFormat) {
    if (rune < start) return false;
    if (rune <= end) return true;
  }
  return false;
}

/// Unicode 16.0.0 General_Category=Cf plus Other_Default_Ignorable_Code_Point
/// (PropList.txt), in ascending order. Variation selectors (U+180B–180D,
/// U+180F, U+FE00–FE0F, U+E0100–E01EF) are deliberately excluded.
const List<(int, int)> _invisibleFormat = [
  (0x00ad, 0x00ad),
  (0x034f, 0x034f),
  (0x0600, 0x0605),
  (0x061c, 0x061c),
  (0x06dd, 0x06dd),
  (0x070f, 0x070f),
  (0x0890, 0x0891),
  (0x08e2, 0x08e2),
  (0x115f, 0x1160),
  (0x17b4, 0x17b5),
  (0x180e, 0x180e),
  (0x200b, 0x200f),
  (0x202a, 0x202e),
  (0x2060, 0x206f),
  (0x3164, 0x3164),
  (0xfeff, 0xfeff),
  (0xffa0, 0xffa0),
  (0xfff0, 0xfffb),
  (0x110bd, 0x110bd),
  (0x110cd, 0x110cd),
  (0x13430, 0x1343f),
  (0x1bca0, 0x1bca3),
  (0x1d173, 0x1d17a),
  (0xe0000, 0xe00ff),
  (0xe01f0, 0xe0fff),
];
