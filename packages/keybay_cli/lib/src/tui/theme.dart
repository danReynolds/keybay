import 'package:fleury/fleury_core.dart';
import 'appearance.dart';

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

  factory KeybayAccents.from(ColorScheme scheme, {bool highContrast = false}) =>
      KeybayAccents(
        accent: CellStyle(foreground: scheme.primary, bold: true),
        attention: CellStyle(foreground: scheme.warning, bold: true),
        placeholder: CellStyle(dim: !highContrast),
      );

  /// Brand and primary actions, independent of semantic success colors.
  final CellStyle accent;

  /// Disclosure: reveal, and revealed text itself.
  final CellStyle attention;

  /// Unfilled input text.
  final CellStyle placeholder;
}

/// The default theme, also used by standalone widgets and tests. The app
/// rebuilds its theme when the appearance preference changes.
///
/// `interactiveStyle` deliberately suppresses the framework's focus cue:
/// Keybay draws its own — a cyan field border and an inverse action label — and
/// letting both apply would double the treatment on every control.
final keybayTheme = keybayThemeFor(const TuiAppearance());

ThemeData keybayThemeFor(TuiAppearance appearance) {
  final high = appearance.contrast == TuiContrast.high;
  final colors = keybayColors.copyWith(
    primary: switch (appearance.accent) {
      TuiAccent.green => const AnsiColor(2),
      TuiAccent.cyan => const AnsiColor(6),
      TuiAccent.blue => const AnsiColor(4),
      TuiAccent.magenta => const AnsiColor(5),
    },
  );
  return ThemeData(
    colorScheme: colors,
    mutedStyle: CellStyle(dim: !high),
    // Terminal-default inverse remains readable with light, dark and NO_COLOR.
    selectionStyle: const CellStyle(inverse: true, bold: true),
    focusedStyle: CellStyle(
      foreground: colors.focus,
      bold: true,
      underline: high,
    ),
    errorStyle: CellStyle(
      foreground: colors.error,
      bold: true,
      underline: true,
    ),
    borderStyle: BorderStyle.single,
    interactiveStyle: CellStyle.interactive(
      focused: CellStyle.none,
      disabled: CellStyle(dim: !high),
    ),
    extensions: [KeybayAccents.from(colors, highContrast: high)],
  );
}

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
