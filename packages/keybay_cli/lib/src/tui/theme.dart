import 'package:fleury/fleury_core.dart';

/// Keybay's palette declared once, as framework colour roles rather than as
/// scattered ANSI indices. Both the framework's own controls — fields, lists,
/// scrollbars, validation — and Keybay's chrome resolve from this, so there is
/// a single place to change a role and a single place to audit one.
///
/// Bright red rather than the scheme's default red: destructive actions must
/// stay legible against the muted borders around them.
const keybayColors = ColorScheme(
  primary: AnsiColor(2),
  focus: AnsiColor(6),
  success: AnsiColor(2),
  warning: AnsiColor(3),
  error: AnsiColor(9),
);

/// The three style roles the framework has no opinion about.
///
/// [ThemeData] already carries a `CellStyle` for muted, selection, focus and
/// error, and Keybay reads those straight from it rather than restating them.
/// What it has no role for is a primary-action style, a disclosure style and a
/// placeholder style: the framework expects a widget to compose those from
/// [ColorScheme]. Buttons use Fleury's [ButtonVariant] directly; these three
/// roles style the surrounding application chrome.
final class KeybayAccents {
  const KeybayAccents({
    required this.accent,
    required this.attention,
    required this.placeholder,
  });

  factory KeybayAccents.from(ColorScheme scheme) => KeybayAccents(
    accent: CellStyle(foreground: scheme.success, bold: true),
    attention: CellStyle(foreground: scheme.warning, bold: true),
    // Grey rather than dim, so unfilled input stays distinct from a disabled
    // field — the framework's widget-level default is dim.
    placeholder: const CellStyle(foreground: RgbColor(0x90, 0x90, 0x90)),
  );

  /// Primary actions and success.
  final CellStyle accent;

  /// Disclosure: reveal, and revealed text itself.
  final CellStyle attention;

  /// Unfilled input text.
  final CellStyle placeholder;
}

/// The theme handed to the whole invocation. `mutedStyle` is left at the
/// framework default, which is already the dim attribute Keybay wants.
///
/// `interactiveStyle` deliberately suppresses the framework's focus cue:
/// Keybay draws its own — a cyan field border and an inverse action label — and
/// letting both apply would double the treatment on every control.
final keybayTheme = ThemeData(
  colorScheme: keybayColors,
  // The current row needs a background that stays readable under the inverse
  // focus cue painted over it, rather than the default inverse.
  selectionStyle: const CellStyle(
    foreground: RgbColor(0xa7, 0xd7, 0xb7),
    background: RgbColor(0x27, 0x3e, 0x31),
    bold: true,
  ),
  focusedStyle: CellStyle(foreground: keybayColors.focus, bold: true),
  errorStyle: CellStyle(foreground: keybayColors.error, bold: true),
  interactiveStyle: const CellStyle.interactive(focused: CellStyle.none),
  extensions: [KeybayAccents.from(keybayColors)],
);

/// Framework roles are already reachable as `context.theme.errorStyle` through
/// Fleury's own `FleuryThemeContext`; this adds only Keybay's three.
extension KeybayAccentAccess on BuildContext {
  /// Falls back to the ambient scheme when no extension is registered, so a
  /// subtree rendered outside [keybayTheme] still styles coherently.
  KeybayAccents get accents {
    final data = Theme.of(this);
    return data.extension<KeybayAccents>() ??
        KeybayAccents.from(data.colorScheme);
  }
}
