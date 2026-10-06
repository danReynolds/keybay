import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart' show Radio;

import 'chrome.dart';
import 'model.dart';

String _idleExitLabel(Duration? timeout) {
  if (timeout == null) return 'Off';
  if (timeout.inMicroseconds % Duration.microsecondsPerMinute == 0) {
    final minutes = timeout.inMinutes;
    return '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
  }
  final seconds = timeout.inSeconds;
  return '$seconds ${seconds == 1 ? 'second' : 'seconds'}';
}

/// Security, Data and Appearance. The model keeps the current
/// category as a view so confirmations can name their cancel target.
final class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.model});
  final TuiModel model;
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

typedef _SettingsAction = ({
  String shortcut,
  String label,
  TuiView view,
  String description,
});

final class _SettingsScreenState extends State<SettingsScreen> {
  final _menu = ListController(initialIndex: 0);
  final _actions = ListController(initialIndex: 0);
  final _menuFocus = FocusNode();
  final _contentFocus = FocusNode();
  final _appearanceFocus = List.generate(5, (_) => FocusNode());
  List<FocusNode> get _appearanceNodes => [_contentFocus, ..._appearanceFocus];
  bool get _appearanceHasFocus =>
      _appearance && _appearanceNodes.any((n) => n.hasFocus);
  int? _hoveredMenu;
  int? _hoveredAction;
  TuiModel get model => widget.model;
  bool get _data => model.view == TuiView.data;
  bool get _appearance => model.view == TuiView.appearance;
  int get _categoryIndex => _appearance
      ? 2
      : _data
      ? 1
      : 0;

  @override
  void dispose() {
    _menu.dispose();
    _actions.dispose();
    _menuFocus.dispose();
    _contentFocus.dispose();
    for (final node in _appearanceFocus) {
      node.dispose();
    }
    super.dispose();
  }

  void _open(TuiView view) {
    if (!model.busy) model.navigate(view);
  }

  void _category(int index) {
    if (index == _categoryIndex) return;
    _actions.currentIndex = 0;
    _hoveredAction = null;
    _open([TuiView.security, TuiView.data, TuiView.appearance][index]);
  }

  List<_SettingsAction> get _categoryActions => [
    if (!_data) ...[
      if (!model.hasPassphrase)
        (
          shortcut: 'p',
          label: 'Add passphrase',
          view: TuiView.passphrase,
          description: 'Require a passphrase when opening this store.',
        ),
      if (model.hasPassphrase && !model.hasPasskeys)
        (
          shortcut: 'x',
          label: 'Remove passphrase',
          view: TuiView.removePassphrase,
          description: 'Remove the passphrase. Keep platform protection.',
        ),
      if (model.supportsHardware)
        (
          shortcut: 'h',
          label: 'Add hardware key',
          view: TuiView.hardware,
          description:
              'Add a physical FIDO2 key as an alternative unlock method.',
        ),
      if (model.hasPasskeys)
        (
          shortcut: 'm',
          label: 'Unlock methods',
          view: TuiView.methods,
          description: 'Inspect or remove a configured unlock method.',
        ),
    ] else ...[
      (
        shortcut: 'c',
        label: 'Clear all records',
        view: TuiView.clear,
        description: 'Delete every saved key and value.',
      ),
      (
        shortcut: 'r',
        label: 'Reset Keybay',
        view: TuiView.reset,
        description: 'Delete all saved keys and remove their unlock methods.',
      ),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    _menu.currentIndex = _categoryIndex;
    final actions = _categoryActions;
    _actions.currentIndex = (_actions.currentIndex ?? 0).clamp(
      0,
      actions.length - 1,
    );
    return KeyBindings(
      bindings: [
        KeyBinding(KeyCode.escape, onTrigger: (_) => _open(TuiView.browse)),
        KeyBinding(KeyCode.s, onTrigger: (_) => _category(0)),
        KeyBinding(KeyCode.d, onTrigger: (_) => _category(1)),
        KeyBinding(KeyCode.a, onTrigger: (_) => _category(2)),
        KeyBinding(
          KeyCode.arrowRight,
          onTrigger: (event) {
            if (_menuFocus.hasFocus) {
              _contentFocus.requestFocus();
            } else {
              event.bubble();
            }
          },
        ),
        KeyBinding(
          KeyCode.arrowLeft,
          onTrigger: (event) {
            if (_contentFocus.hasFocus || _appearanceHasFocus) {
              _menuFocus.requestFocus();
            } else {
              event.bubble();
            }
          },
        ),
        for (final direction in [KeyCode.arrowDown, KeyCode.arrowUp])
          KeyBinding(
            direction,
            onTrigger: (event) {
              if (!_appearanceHasFocus) {
                event.bubble();
                return;
              }
              final nodes = _appearanceNodes;
              final index = nodes.indexWhere((n) => n.hasFocus);
              nodes[(index + (direction == KeyCode.arrowDown ? 1 : -1)).clamp(
                    0,
                    nodes.length - 1,
                  )]
                  .requestFocus();
            },
          ),
        for (final action in _appearance ? <_SettingsAction>[] : actions)
          KeyBinding(
            KeyCode.char(action.shortcut),
            onTrigger: (_) => _open(action.view),
          ),
      ],
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          maxWidth: 104,
          child: KeybayFrame(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Settings', style: CellStyle(bold: true)),
                const SizedBox(height: 1),
                Expanded(
                  child: LayoutBuilder(
                    builder: (_, size) {
                      final narrow = (size.maxCols ?? 76) < 60;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: narrow ? 12 : 16,
                            height: 3,
                            child: _categoryList(),
                          ),
                          const SizedBox(width: 1),
                          SizedBox(
                            width: 1,
                            child: Text(
                              List.filled(size.maxRows ?? 13, '│').join('\n'),
                              style: context.theme.mutedStyle,
                              allowSelect: false,
                            ),
                          ),
                          const SizedBox(width: 2),
                          Expanded(
                            child: _appearance
                                ? _appearanceContent()
                                : _content(actions, narrow: narrow),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 1),
                // Describe what the focused pane handles. Action shortcuts
                // stay on the action rows themselves.
                LayoutBuilder(
                  builder: (_, size) => Row(
                    children: [
                      Text(
                        _menuFocus.hasFocus
                            ? '→ actions'
                            : _contentFocus.hasFocus || _appearanceHasFocus
                            ? '← category'
                            : '',
                        style: context.theme.mutedStyle,
                      ),
                      const Expanded(child: SizedBox.shrink()),
                      TuiAction(
                        label: 'Back',
                        shortcut: 'Esc',
                        onPressed: () => _open(TuiView.browse),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _categoryList() => FocusDetector(
    onFocusChange: (_) => setState(() {}),
    child: ListView.builder(
      controller: _menu,
      focusNode: _menuFocus,
      autofocus: model.view == TuiView.settings,
      itemCount: 3,
      onFocusedItemChanged: _category,
      onSelect: (_) => _contentFocus.requestFocus(),
      itemBuilder: (_, i, highlighted) => _row(
        label: ['Security', 'Data', 'Appearance'][i],
        current: highlighted,
        focused: highlighted && _menuFocus.hasFocus,
        active: i == _categoryIndex,
        hovered: _hoveredMenu == i,
        onHover: (value) => setState(() => _hoveredMenu = value ? i : null),
        onPressed: () {
          _category(i);
          _menuFocus.requestFocus();
        },
      ),
    ),
  );

  Widget _appearanceContent() => FocusDetector(
    onFocusChange: (_) => setState(() {}),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Appearance', style: CellStyle(bold: true)),
        const SizedBox(height: 1),
        const Text('Accent'),
        for (final accent in TuiAccent.values)
          Radio<TuiAccent>(
            label: accent.label,
            focusNode: _appearanceNodes[accent.index],
            value: accent,
            groupValue: model.appearance.accent,
            style: const CellStyle.interactive(
              focused: CellStyle(inverse: true),
            ),
            onChanged: model.busy
                ? null
                : (accent) => model.setAppearance(
                    model.appearance.copyWith(accent: accent),
                  ),
          ),
        const SizedBox(height: 1),
        const Text('Contrast'),
        for (final contrast in TuiContrast.values)
          Radio<TuiContrast>(
            label: contrast.label,
            focusNode:
                _appearanceNodes[TuiAccent.values.length + contrast.index],
            value: contrast,
            groupValue: model.appearance.contrast,
            style: const CellStyle.interactive(
              focused: CellStyle(inverse: true),
            ),
            onChanged: model.busy
                ? null
                : (contrast) => model.setAppearance(
                    model.appearance.copyWith(contrast: contrast),
                  ),
          ),
      ],
    ),
  );

  Widget _content(
    List<_SettingsAction> actions, {
    required bool narrow,
  }) => LayoutBuilder(
    builder: (_, size) {
      final labelWidth = ((size.maxCols ?? 56) - 6).clamp(1, 100);
      final menuRows = actions.fold(
        0,
        (rows, action) =>
            rows + ((action.label.length + 1) / labelWidth).ceil(),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_data ? 'Data' : 'Security', style: const CellStyle(bold: true)),
          const SizedBox(height: 1),
          if (!_data) ...[
            Text(
              'Passphrase: ${model.hasPassphrase ? 'On' : 'Off'}',
              // Amber is Keybay's "note this" role, not its error role:
              // platform-only is supported, but it is the weaker state and
              // should not be the quieter of the two.
              style: model.hasPassphrase
                  ? context.accents.accent
                  : context.accents.attention,
            ),
            if (model.hasPasskeys)
              Text(
                'Passkeys: ${model.methods.where((m) => m.rpId != null).length}',
              ),
            Text(
              'Idle exit: ${_idleExitLabel(model.idleTimeout)}',
              style: context.theme.mutedStyle,
            ),
            const SizedBox(height: 1),
          ],
          SizedBox(
            // A stable key keeps the shared focus node attached as the
            // surrounding content changes with the category.
            key: const ValueKey('settings-actions'),
            height: menuRows,
            child: _actionList(actions),
          ),
          const SizedBox(height: 1),
          Text(
            actions[_actions.currentIndex ?? 0].description,
            maxLines: narrow ? 3 : 2,
            style: context.theme.mutedStyle,
          ),
        ],
      );
    },
  );

  Widget _actionList(List<_SettingsAction> actions) => FocusDetector(
    onFocusChange: (_) => setState(() {}),
    child: ListView.builder(
      controller: _actions,
      focusNode: _contentFocus,
      autofocus: model.view != TuiView.settings,
      itemCount: actions.length,
      onFocusedItemChanged: (_) => setState(() {}),
      onSelect: (i) => _open(actions[i].view),
      itemBuilder: (_, i, highlighted) => _row(
        label: actions[i].label,
        current: highlighted,
        shortcut: actions[i].shortcut,
        focused: highlighted && _contentFocus.hasFocus,
        hovered: _hoveredAction == i,
        onHover: (value) => setState(() => _hoveredAction = value ? i : null),
        onPressed: () => _open(actions[i].view),
      ),
    ),
  );

  Widget _row({
    required String label,
    String? shortcut,
    required bool current,
    required bool focused,
    bool active = false,
    required bool hovered,
    required void Function(bool) onHover,
    required void Function() onPressed,
  }) {
    final style =
        (focused
                ? context.theme.selectionStyle
                : active
                ? CellStyle(foreground: context.theme.selectionStyle.foreground)
                : CellStyle.none)
            .copyWith(bold: focused, underline: hovered && !model.busy);
    // This row owns its focus and current-item paint. Reset the list's
    // inherited selection text style before applying those explicit styles.
    return DefaultTextStyle(
      style: context.theme.textStyle,
      child: MouseRegion(
        cursor: model.busy ? MouseCursor.basic : MouseCursor.pointer,
        onEnter: () => onHover(true),
        onExit: () => onHover(false),
        child: Semantics(
          role: SemanticRole.button,
          label: label,
          enabled: !model.busy,
          focused: focused,
          selected: active,
          actions: {if (!model.busy) SemanticAction.activate},
          onAction: (_) {
            if (!model.busy) onPressed();
          },
          child: Container(
            color: style.background,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${current ? '›' : ' '} ${shortcut == null ? '' : '[$shortcut] '}',
                  style: style.copyWith(bold: true),
                  allowSelect: false,
                ),
                Expanded(
                  child: Text(
                    '$label${shortcut == null ? '' : '…'}',
                    style: style,
                    allowSelect: false,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
