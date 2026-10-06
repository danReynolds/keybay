/// Local presentation choices. No vault or credential state belongs here.
enum TuiAccent {
  green('Green'),
  cyan('Cyan'),
  blue('Blue'),
  magenta('Magenta');

  const TuiAccent(this.label);
  final String label;
}

enum TuiContrast {
  normal('Normal'),
  high('High');

  const TuiContrast(this.label);
  final String label;
}

final class TuiAppearance {
  const TuiAppearance({
    this.accent = TuiAccent.green,
    this.contrast = TuiContrast.normal,
  });

  final TuiAccent accent;
  final TuiContrast contrast;

  TuiAppearance copyWith({TuiAccent? accent, TuiContrast? contrast}) =>
      TuiAppearance(
        accent: accent ?? this.accent,
        contrast: contrast ?? this.contrast,
      );

  @override
  bool operator ==(Object other) =>
      other is TuiAppearance &&
      other.accent == accent &&
      other.contrast == contrast;

  @override
  int get hashCode => Object.hash(accent, contrast);
}
