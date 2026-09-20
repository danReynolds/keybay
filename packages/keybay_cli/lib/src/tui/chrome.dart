import 'dart:async';

import 'package:fleury/fleury_core.dart';

import 'model.dart';

export 'theme.dart';

bool _printableAscii(int point) => point >= 32 && point <= 126;

const keyTextPolicy = TextEditPolicy(
  maxCodeUnits: 120,
  allowCodePoint: _printableAscii,
);

/// Pending-operation indicator. Messages are toasts now; "still working" is
/// not a message — a toast that auto-dismisses cannot represent it — so it
/// keeps its own reserved row.
final class BusyIndicator extends StatelessWidget {
  const BusyIndicator({
    super.key,
    required this.model,
    this.compact = false,
    this.label = 'Working',
  });
  final TuiModel model;
  final bool compact;
  final String label;

  @override
  Widget build(BuildContext context) {
    final height = compact ? 1 : 3;
    if (!model.showsBusy) return SizedBox(height: height);
    return SizedBox(
      height: height,
      child: Align(
        alignment: Alignment.bottomRight,
        child: Semantics(
          role: SemanticRole.notification,
          label: label,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Spinner(),
              Text(' $label…', style: context.theme.mutedStyle),
            ],
          ),
        ),
      ),
    );
  }
}

final class Rule extends StatelessWidget {
  const Rule({super.key});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, size) => Text(
      '─' * (size.maxCols ?? 80),
      maxLines: 1,
      style: context.theme.mutedStyle,
      allowSelect: false,
    ),
  );
}

final class ResizePrompt extends StatelessWidget {
  const ResizePrompt({super.key, required this.model, this.draft = false});
  final TuiModel model;
  final bool draft;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Resize to at least 40×24 or 80×20.'),
        if (draft) const Text('Draft kept hidden.'),
        TuiAction(
          label: 'Quit',
          autofocus: true,
          onPressed: () => unawaited(model.close()),
        ),
      ],
    ),
  );
}

/// One escape-and-wrap of a value. Escaping allocates a full copy and wrapping
/// allocates every row, so both are computed once per (value, geometry) pair
/// and reused across layout passes instead of once per frame.
final class _WrappedValue {
  factory _WrappedValue(String source, int available, int? limit) {
    final lines = safeTuiText(source).split('\n');
    List<String> wrap(int width) => [
      for (final line in lines) ...wrapEscapedLine(line, width),
    ];
    var rows = wrap(available);
    // Reserve a gutter only when scrolling is necessary, then re-wrap into it.
    final scrolling = limit != null && rows.length > limit;
    final width = scrolling ? (available - 1).clamp(1, 10000) : available;
    if (scrolling) rows = wrap(width);
    return _WrappedValue._(source, available, limit, scrolling, width, rows);
  }

  _WrappedValue._(
    this.source,
    this.available,
    this.limit,
    this.scrolling,
    this.width,
    this.rows,
  );

  final String source;
  final int available;
  final int? limit;
  final bool scrolling;
  final int width;
  final List<String> rows;

  bool matches(String source, int available, int? limit) =>
      identical(this.source, source) &&
      this.available == available &&
      this.limit == limit;
}

/// Build only the visible rows of a bounded, escaped value view. The wrap is
/// memoised so a 1 MiB record is not re-escaped and re-sliced on every frame.
final class ValueView extends StatefulWidget {
  const ValueView({
    super.key,
    required this.text,
    this.focusNode,
    this.maxRows,
    this.textAlign = TextAlign.left,
  });
  final String text;
  final FocusNode? focusNode;
  final int? maxRows;
  final TextAlign textAlign;
  @override
  State<ValueView> createState() => _ValueViewState();
}

final class _ValueViewState extends State<ValueView> {
  _WrappedValue? _cache;

  _WrappedValue _wrap(int available, int? limit) {
    final cached = _cache;
    if (cached != null && cached.matches(widget.text, available, limit)) {
      return cached;
    }
    return _cache = _WrappedValue(widget.text, available, limit);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, size) {
      final available = (size.maxCols ?? 40).clamp(1, 10000);
      final wrapped = _wrap(available, widget.maxRows ?? size.maxRows);
      final list = ListView.builder(
        // This is scrollable text, not a menu of selectable lines. Leaving
        // selection enabled adds a second highlight and overrides disclosure
        // styling on one line as the user scrolls.
        selectable: false,
        // Reaching the value's edge must not navigate the surrounding keys.
        // Cross-axis arrows still bubble for the explicit return to the list.
        edgeBehavior: EdgeBehavior.contain,
        focusNode: widget.focusNode,
        scrollbar: wrapped.scrolling,
        itemCount: wrapped.rows.length,
        itemBuilder: (_, index, _) => SizedBox(
          width: wrapped.width,
          child: ExcludeSemantics(
            // Selection policy does not redact Text's semantic label/value.
            // Exclude only secret text; keep the viewer's scroll/focus surface.
            child: Text(
              wrapped.rows[index],
              allowSelect: false,
              softWrap: false,
              textAlign: widget.textAlign,
            ),
          ),
        ),
      );
      final maxRows = widget.maxRows;
      return maxRows == null
          ? list
          : SizedBox(
              height: wrapped.rows.length.clamp(1, maxRows),
              child: list,
            );
    },
  );
}

/// Shared column widths keep action rows aligned as labels and focus change.
final class ActionGrid extends StatelessWidget {
  const ActionGrid({super.key, required this.actions, this.maxColumns = 3});
  final List<TuiAction> actions;
  final int maxColumns;
  int get _widestCell => actions.fold(
    0,
    (width, action) =>
        action._displayWidth > width ? action._displayWidth : width,
  );

  /// Each column is only as wide as the actions actually in it, so a short
  /// label beside a long one does not inherit its width. Column count is still
  /// decided from the widest cell, which guarantees the row fits.
  int _widthOfColumn(int column, int columns) {
    var widest = 0;
    for (var i = column; i < actions.length; i += columns) {
      if (actions[i]._displayWidth > widest) widest = actions[i]._displayWidth;
    }
    return widest;
  }

  int _columnsFor(int width) {
    final columns = ((width + 2) ~/ (_widestCell + 2)).clamp(1, maxColumns);
    // Keep the vault's four record actions together on one or two rows.
    return maxColumns == 4 && columns == 3 ? 2 : columns;
  }

  int rowsFor(int width) => (actions.length / _columnsFor(width)).ceil();
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, size) {
      final columns = _columnsFor(size.maxCols ?? 60);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var start = 0; start < actions.length; start += columns)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (
                  var i = start;
                  i < start + columns && i < actions.length;
                  i++
                ) ...[
                  if (i != start) const SizedBox(width: 2),
                  SizedBox(
                    width: _widthOfColumn(i - start, columns),
                    child: actions[i],
                  ),
                ],
              ],
            ),
        ],
      );
    },
  );
}

/// One action cell. Fleury owns interaction and semantics; Keybay supplies
/// the label, decorative shortcut and styling.
final class TuiAction extends StatelessWidget {
  const TuiAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.shortcut,
    this.reservedLabel,
    this.variant = ButtonVariant.normal,
    this.focusNode,
    this.autofocus = false,
  });

  final String label;
  final String? shortcut;

  /// Widest label this cell will ever show. A Reveal/Hide toggle reserves
  /// `Reveal` so changing the label cannot shift the actions beside it.
  final String? reservedLabel;

  final ButtonVariant variant;
  final void Function()? onPressed;
  final FocusNode? focusNode;
  final bool autofocus;

  String get _hint => shortcut == null ? '' : '[$shortcut] ';
  int get _displayWidth => _hint.length + (reservedLabel ?? label).length;

  @override
  Widget build(BuildContext context) => Button(
    appearance: ButtonAppearance.plain,
    semanticLabel: label,
    variant: variant,
    focusNode: focusNode,
    autofocus: autofocus,
    onPressed: onPressed,
    style: const CellStyle.interactive(
      focused: CellStyle(inverse: true),
      hovered: CellStyle(underline: true),
      disabled: CellStyle(dim: true),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (shortcut != null)
          Text(_hint, allowSelect: false, style: const CellStyle(bold: true)),
        Text(label, allowSelect: false),
      ],
    ),
  );
}
