import 'package:characters/characters.dart';
import 'package:fleury/fleury_core.dart';

/// Code points that never reach the terminal as themselves when Keybay shows a
/// stored value: C0 and C1 controls (except LF, which is layout), DEL, line and
/// paragraph separators, lone surrogates, every Unicode format character or
/// other default-ignorable code point, and every Prepend character. Each can
/// drive the terminal or make the display disagree with the stored bytes:
/// bidi overrides and isolates, joiners and zero-width marks, tag characters
/// and fillers, and prepended marks and letters that fold the next character,
/// or an escape's backslash, into their own cell.
///
/// Variation selectors are judged in context by [escapeCluster]. Everything
/// else printable (accents, CJK, emoji) renders as itself.
bool mustEscapeRune(int rune) =>
    rune < 0x20 && rune != 0x0a ||
    rune >= 0x7f && rune <= 0x9f ||
    rune == 0x2028 ||
    rune == 0x2029 ||
    rune >= 0xd800 && rune <= 0xdfff ||
    rune >= 0xad && _inEscapedRanges(rune);

/// Whether [text] shows nothing but printable ASCII, which is always drawn as
/// itself one cell per character; LF is allowed when [allowNewlines] is set.
bool isPrintableAscii(String text, {bool allowNewlines = false}) {
  for (var index = 0; index < text.length; index++) {
    final unit = text.codeUnitAt(index);
    if (unit >= 0x20 && unit < 0x7f || allowNewlines && unit == 0x0a) continue;
    return false;
  }
  return true;
}

/// Whether [text] contains anything [escapeCluster] shows escaped: whether a
/// live editor must give way to a read-only escaped preview, and whether `get`
/// must refuse the value. A backslash alone does not count; LF counts only
/// when [allowNewlines] is false.
bool needsTuiEscaping(String text, {required bool allowNewlines}) {
  var index = 0;
  while (index < text.length) {
    final unit = text.codeUnitAt(index);
    if (unit == 0x0a) {
      if (!allowNewlines) return true;
    } else if (unit < 0x20 || unit >= 0x7f) {
      break;
    }
    index++;
  }
  if (index == text.length) return false;
  // Printable ASCII before the last one is its own cluster; that last one may
  // join what follows it.
  for (final cluster in text.substring(index == 0 ? 0 : index - 1).characters) {
    if (cluster == '\n') {
      if (!allowNewlines) return true;
    } else if (!_isPlainAscii(cluster) && _hiddenRunes(cluster) != null) {
      return true;
    }
  }
  return false;
}

/// The display form of one grapheme cluster: [cluster] itself when every code
/// point shows as itself, otherwise a copy with backslashes doubled and each
/// hidden code point written as `\u{hex}`. LF stays a line break.
///
/// A code point is hidden when [mustEscapeRune] says so, when it is a
/// variation selector that does not choose the presentation of the emoji
/// before it, or when everything the cluster would show draws no cells (a
/// stray combining mark). No stored code point can vanish from the display.
String escapeCluster(String cluster) {
  if (_isPlainAscii(cluster)) return cluster;
  final hidden = _hiddenRunes(cluster);
  if (hidden == null && !cluster.contains(r'\')) return cluster;
  final out = StringBuffer();
  for (final (index, rune) in cluster.runes.indexed) {
    if (hidden != null && hidden[index]) {
      out.write('\\u{${rune.toRadixString(16)}}');
    } else if (rune == 0x5c) {
      out.write(r'\\');
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

const _widths = DefaultWidthResolver();

/// A single printable ASCII character other than backslash: the common case,
/// always drawn as itself in one cell.
bool _isPlainAscii(String cluster) {
  if (cluster.length != 1) return false;
  final unit = cluster.codeUnitAt(0);
  return unit >= 0x20 && unit < 0x7f && unit != 0x5c;
}

/// Which code points of [cluster] show escaped, or null when none do.
List<bool>? _hiddenRunes(String cluster) {
  if (cluster == '\n') return null;
  List<bool>? hidden;
  int? base;
  var index = 0;
  for (final rune in cluster.runes) {
    final bool hide;
    if (rune == 0x0a || rune == 0x5c) {
      hide = false;
      base = null;
    } else if (mustEscapeRune(rune)) {
      hide = true;
      base = null;
    } else if (_isVariationSelector(rune)) {
      // One text or emoji presentation selector may follow an emoji; any other
      // selector would only hide data behind the character it follows.
      hide =
          !(base != null &&
              (rune == 0xfe0e || rune == 0xfe0f) &&
              _takesPresentation(base));
      base = null;
    } else {
      hide = false;
      base = rune;
    }
    if (hide) hidden ??= List<bool>.filled(index, false, growable: true);
    hidden?.add(hide);
    index++;
  }
  // What is shown as itself must take a cell, or it would vanish.
  if (hidden == null) {
    return _widths.widthOfGrapheme(cluster, CellWidthPolicy.spec) == 0
        ? List<bool>.filled(index, true)
        : null;
  }
  final kept = StringBuffer();
  for (final (position, rune) in cluster.runes.indexed) {
    if (!hidden[position] && rune != 0x0a) kept.writeCharCode(rune);
  }
  final drawsNothing = '$kept'.characters.every(
    (shown) => _widths.widthOfGrapheme(shown, CellWidthPolicy.spec) == 0,
  );
  return kept.isNotEmpty && drawsNothing
      ? List<bool>.filled(index, true)
      : hidden;
}

bool _isVariationSelector(int rune) =>
    rune >= 0xfe00 && rune <= 0xfe0f ||
    rune >= 0x180b && rune <= 0x180d ||
    rune == 0x180f ||
    rune >= 0xe0100 && rune <= 0xe01ef;

/// Whether a text or emoji presentation selector after [base] chooses how the
/// base is drawn: a keycap base, or an Extended_Pictographic code point that is
/// not itself a mark. The segmenter joins `base ZWJ base` into one cluster
/// exactly when the base is Extended_Pictographic (UAX #29 GB11), so this
/// follows the same tables the renderer segments with.
bool _takesPresentation(int base) {
  if (base == 0x23 || base == 0x2a || base >= 0x30 && base <= 0x39) {
    return true;
  }
  final glyph = String.fromCharCode(base);
  return 'x$glyph'.characters.length == 2 &&
      '$glyph‍$glyph'.characters.length == 1;
}

bool _inEscapedRanges(int rune) {
  var low = 0;
  var high = _escapedRanges.length - 1;
  while (low <= high) {
    final middle = (low + high) >> 1;
    final (start, end) = _escapedRanges[middle];
    if (rune < start) {
      high = middle - 1;
    } else if (rune > end) {
      low = middle + 1;
    } else {
      return true;
    }
  }
  return false;
}

/// Unicode 16.0.0 General_Category=Cf, Other_Default_Ignorable_Code_Point
/// (PropList.txt) and Grapheme_Cluster_Break=Prepend, sorted and disjoint.
/// Variation selectors (U+180B–180D, U+180F, U+FE00–FE0F, U+E0100–E01EF) are
/// deliberately excluded; [escapeCluster] judges them in context.
const List<(int, int)> _escapedRanges = [
  (0x00ad, 0x00ad),
  (0x034f, 0x034f),
  (0x0600, 0x0605),
  (0x061c, 0x061c),
  (0x06dd, 0x06dd),
  (0x070f, 0x070f),
  (0x0890, 0x0891),
  (0x08e2, 0x08e2),
  (0x0d4e, 0x0d4e),
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
  (0x111c2, 0x111c3),
  (0x113d1, 0x113d1),
  (0x1193f, 0x1193f),
  (0x11941, 0x11941),
  (0x11a3a, 0x11a3a),
  (0x11a84, 0x11a89),
  (0x11d46, 0x11d46),
  (0x11f02, 0x11f02),
  (0x13430, 0x1343f),
  (0x1bca0, 0x1bca3),
  (0x1d173, 0x1d17a),
  (0xe0000, 0xe00ff),
  (0xe01f0, 0xe0fff),
];
