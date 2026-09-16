import 'dart:async';

import 'package:fleury/fleury_core.dart';

import 'chrome.dart';
import 'model.dart';

/// The C1 finder: one centred list of names with constant masks, a shared
/// action grid, and a bounded revealed-value column on the selected row.
final class Vault extends StatefulWidget {
  const Vault({super.key, required this.model});
  final TuiModel model;
  @override
  State<Vault> createState() => _VaultState();
}

final class _VaultState extends State<Vault> {
  final _searchFocus = FocusNode();
  final _listFocus = FocusNode();
  final _actionFocus = FocusNode();
  final _valueFocus = FocusNode();
  final _newFocus = FocusNode();
  final _list = ListController(initialIndex: 0);
  late final TextEditingController _search;
  TuiModel get model => widget.model;

  void _focusResults({bool selectFirst = false}) {
    final names = model.visibleKeys;
    final target = !selectFirst && names.contains(model.selectedKey)
        ? model.selectedKey
        : names.firstOrNull;
    if (target == null) {
      if (model.query.isEmpty) _newFocus.requestFocus();
      return;
    }
    if (target != model.selectedKey) model.select(target);
    if (_listFocus.isAttached) {
      _listFocus.requestFocus();
    } else {
      // A corrected zero-result query may have a list waiting to mount.
      // Keep search focus until it exists; New key is not the result target.
      TuiBinding.of(context).addPostFrameCallback((_) {
        if (mounted && model.view == TuiView.browse) {
          _focusResults(selectFirst: selectFirst);
        }
      });
    }
  }

  void _leaveSearch() {
    _search.value = TextEditingValue.empty();
    model.search('');
    _focusResults();
  }

  String get _hint {
    final escape = model.revealed
        ? 'Esc hide'
        : model.query.isNotEmpty
        ? 'Esc clear'
        : null;
    if (_searchFocus.hasFocus) {
      return [
        if (model.visibleKeys.isNotEmpty) 'Enter results',
        if (escape != null) escape,
      ].join(' · ');
    }
    if (_valueFocus.hasFocus) return '← keys · Esc hide';
    if (_listFocus.hasFocus) {
      if (model.revealed) return '→ value · Enter edit · Esc hide';
      return model.query.isEmpty
          ? 'Enter edit · / search'
          : 'Enter edit · / search · Esc clear';
    }
    return escape ?? '';
  }

  /// Buttons and accelerators read this same map, so a disabled action is
  /// unreachable from both.
  Map<String, void Function()?> get _actions {
    final record =
        !model.busy &&
        model.selectedKey != null &&
        model.visibleKeys.isNotEmpty;
    return {
      ' ': record ? () => unawaited(model.read()) : null,
      'c': record && model.copyText != null
          ? () => unawaited(model.read(copy: true))
          : null,
      'e': record ? () => unawaited(model.read(edit: true)) : null,
      'd': record ? () => model.navigate(TuiView.delete) : null,
      'n': model.busy ? null : () => model.navigate(TuiView.create),
      's': model.busy ? null : () => model.navigate(TuiView.settings),
      'q': () => unawaited(model.close()),
    };
  }

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(
      text: model.query,
      editPolicy: keyTextPolicy,
    );
  }

  @override
  void dispose() {
    _search.dispose();
    _list.dispose();
    _searchFocus.dispose();
    _listFocus.dispose();
    _actionFocus.dispose();
    _valueFocus.dispose();
    _newFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Built-in focus subscription keeps hints and row styles in step with
    // keyboard focus even when no model value changes.
    FocusManager.of(context);
    final names = model.visibleKeys;
    final index = names.indexOf(model.selectedKey ?? '');
    _list.currentIndex = index < 0 ? null : index;
    final callbacks = _actions;
    final revealed = model.revealed ? model.valueText : null;
    final longest = model.valueDisplayWidth;
    final actions = <TuiAction>[
      TuiAction(
        label: model.revealed ? 'Hide' : 'Reveal',
        shortcut: 'Space',
        reservedLabel: 'Reveal',
        variant: ButtonVariant.warning,
        focusNode: _actionFocus,
        onPressed: callbacks[' '],
      ),
      TuiAction(label: 'Copy', shortcut: 'c', onPressed: callbacks['c']),
      TuiAction(label: 'Edit', shortcut: 'e', onPressed: callbacks['e']),
      TuiAction(
        label: 'Delete',
        shortcut: 'd',
        variant: ButtonVariant.error,
        onPressed: callbacks['d'],
      ),
      TuiAction(
        label: 'New key',
        shortcut: 'n',
        variant: ButtonVariant.success,
        focusNode: _newFocus,
        autofocus: names.isEmpty,
        onPressed: callbacks['n'],
      ),
      TuiAction(label: 'Settings', shortcut: 's', onPressed: callbacks['s']),
      TuiAction(label: 'Quit', shortcut: 'q', onPressed: callbacks['q']),
    ];
    return KeyBindings(
      bindings: [
        KeyBinding(
          KeyCode.char('/'),
          label: 'search',
          onTrigger: (event) {
            if (_searchFocus.hasFocus) {
              event.bubble();
            } else {
              _searchFocus.requestFocus();
            }
          },
        ),
        KeyBinding(
          KeyCode.arrowDown,
          label: 'next',
          includeRepeats: true,
          onTrigger: (event) {
            if (_searchFocus.hasFocus) {
              _focusResults(selectFirst: true);
            } else {
              event.bubble();
            }
          },
        ),
        KeyBinding(
          KeyCode.arrowUp,
          includeRepeats: true,
          onTrigger: (event) {
            if (_listFocus.hasFocus && _list.currentIndex == 0) {
              _searchFocus.requestFocus();
            } else {
              event.bubble();
            }
          },
        ),
        KeyBinding(
          KeyCode.arrowRight,
          label: model.revealed ? 'scroll value' : null,
          onTrigger: (event) {
            if (!_listFocus.hasFocus) {
              event.bubble();
            } else if (model.revealed) {
              _valueFocus.requestFocus();
            }
            // While masked or still loading, stay on the key instead of
            // letting spatial traversal jump to an unrelated footer action.
          },
        ),
        KeyBinding(
          KeyCode.arrowLeft,
          onTrigger: (event) {
            if (_valueFocus.hasFocus) {
              _listFocus.requestFocus();
            } else {
              event.bubble();
            }
          },
        ),
        KeyBinding(
          KeyCode.escape,
          label: model.revealed
              ? 'hide'
              : model.query.isEmpty
              ? null
              : 'clear filter',
          onTrigger: (event) {
            if (model.revealed || model.busy) {
              model.hide();
              _focusResults();
            } else if (model.query.isNotEmpty) {
              _leaveSearch();
            } else {
              // Nothing left to conceal or clear. In particular, let the
              // existing Toaster dismiss a notice without moving selection.
              event.bubble();
            }
          },
        ),
        for (final key in callbacks.keys)
          KeyBinding(
            KeyCode.char(key),
            // Read focus and eligibility on press. Enter can hand search
            // focus to results and the next key can arrive before a rebuild.
            onTrigger: (event) {
              if (model.view == TuiView.browse && !_searchFocus.hasFocus) {
                _actions[key]?.call();
              } else {
                event.bubble();
              }
            },
          ),
      ],
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          maxWidth: 80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FocusDetector(
                onFocusChange: (_) => setState(() {}),
                child: Row(
                  children: [
                    Text(
                      '/ ',
                      style: _searchFocus.hasFocus
                          ? context.theme.focusedStyle
                          : context.accents.accent,
                    ),
                    Expanded(
                      child: TextInput(
                        controller: _search,
                        focusNode: _searchFocus,
                        semanticLabel: 'Search key names',
                        placeholder: 'Find a key…',
                        placeholderStyle: context.accents.placeholder,
                        clipboardPolicy: TextClipboardPolicy.disabled,
                        onChanged: (text) {
                          model.search(text);
                          _list.jumpToIndex(0);
                        },
                        onSubmit: (_) => _focusResults(selectFirst: true),
                        onEscape: _leaveSearch,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${names.length} ${names.length == 1 ? 'key' : 'keys'}',
                      style: context.theme.mutedStyle,
                    ),
                  ],
                ),
              ),
              const Rule(),
              if (MediaQuery.sizeOf(context).rows > 24)
                const SizedBox(height: 1),
              Expanded(
                child: LayoutBuilder(
                  builder: (_, size) {
                    final valueRows = ((size.maxRows ?? 8) ~/ 2).clamp(1, 6);
                    // Reserve a stable gutter when the list can scroll,
                    // including expansion of its current row on disclosure.
                    final scrolling =
                        names.length + valueRows - 1 > (size.maxRows ?? 8);
                    final width = (size.maxCols ?? 80) - (scrolling ? 1 : 0);
                    return names.isEmpty
                        ? Text(
                            model.keys.isEmpty
                                // New key already holds focus; say so rather
                                // than leaving a bare dead end.
                                ? 'No keys yet — press n to add one'
                                : 'No matching keys',
                          )
                        : ListView.builder(
                            controller: _list,
                            focusNode: _listFocus,
                            autofocus: true,
                            scrollbar: scrolling,
                            edgeBehavior: EdgeBehavior.bubble,
                            itemCount: names.length,
                            itemKeyBuilder: (i) => names[i],
                            onFocusedItemChanged: (i) {
                              if (i < names.length &&
                                  names[i] != model.selectedKey) {
                                model.select(names[i]);
                              }
                            },
                            onSelect: (_) => _actions['e']?.call(),
                            itemBuilder: (_, i, selected) {
                              final focused = selected && _listFocus.hasFocus;
                              final rowStyle = focused
                                  ? context.theme.selectionStyle
                                  : selected
                                  ? CellStyle(
                                      foreground: context
                                          .theme
                                          .selectionStyle
                                          .foreground,
                                    )
                                  : CellStyle.none;
                              final value = selected ? revealed : null;
                              final name = safeTuiText(names[i]);
                              final nameCells = escapedLineWidth(name);
                              var nameWidth = nameCells.clamp(
                                1,
                                value == null ? width - 12 : (width - 4) ~/ 2,
                              );
                              // Give the name its natural width whenever the
                              // whole value still fits beside it.
                              if (value != null &&
                                  nameCells > nameWidth &&
                                  nameCells + longest + 4 <= width) {
                                nameWidth = nameCells;
                              }
                              // A row click selects; Enter is the explicit edit action.
                              return GestureDetector(
                                onTapDown: (_) {
                                  _list.currentIndex = i;
                                  model.select(names[i]);
                                  _listFocus.requestFocus();
                                },
                                child: Container(
                                  color: selected && _listFocus.hasFocus
                                      ? context.theme.selectionStyle.background
                                      : null,
                                  child: DefaultTextStyle(
                                    style: rowStyle,
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          selected ? '› ' : '  ',
                                          allowSelect: false,
                                        ),
                                        SizedBox(
                                          width: nameWidth,
                                          child: Text(
                                            name,
                                            maxLines: selected ? valueRows : 1,
                                            softWrap: selected,
                                            overflow: TextOverflow.ellipsis,
                                            allowSelect: false,
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        Expanded(
                                          child: value != null
                                              ? DefaultTextStyle(
                                                  style:
                                                      context.accents.attention,
                                                  child: ValueView(
                                                    key: ValueKey(
                                                      model.selectedKey,
                                                    ),
                                                    text: value,
                                                    focusNode: _valueFocus,
                                                    maxRows: valueRows,
                                                    textAlign: TextAlign.right,
                                                  ),
                                                )
                                              : const SizedBox(
                                                  height: 1,
                                                  child: Align(
                                                    alignment:
                                                        Alignment.topRight,
                                                    child: Text(
                                                      '••••••••',
                                                      allowSelect: false,
                                                      style: CellStyle(
                                                        dim: true,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                  },
                ),
              ),
              const Rule(),
              const SizedBox(height: 1),
              ActionGrid(actions: actions, maxColumns: 4),
              const SizedBox(height: 1),
              // Actions advertise their own shortcuts. Reserve this row for
              // app-specific behavior, including the current meaning of Esc.
              SizedBox(
                height: 1,
                child: Text(
                  _hint,
                  style: context.theme.mutedStyle,
                  allowSelect: false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
