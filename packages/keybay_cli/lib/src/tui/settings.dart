import 'package:fleury/fleury_core.dart';

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

/// Security and Data categories over one session. The model keeps the current
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
  int? _hoveredMenu;
  int? _hoveredAction;
  TuiModel get model => widget.model;
  bool get _data => model.view == TuiView.data;

  @override
  void dispose() {
    _menu.dispose();
    _actions.dispose();
    _menuFocus.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  void _open(TuiView view) {
    if (!model.busy) model.navigate(view);
  }

  void _category(int index) {
    if (index == (_data ? 1 : 0)) return;
    _actions.currentIndex = 0;
    _hoveredAction = null;
    _open(index == 1 ? TuiView.data : TuiView.security);
  }

  List<_SettingsAction> get _categoryActions => [
    if (!_data) ...[
      (
        shortcut: 'p',
        label: model.protected ? 'Change passphrase' : 'Add passphrase',
        view: TuiView.passphrase,
        description: model.protected
            ? 'Replace the passphrase used to open this store.'
            : 'Require a passphrase when opening this store.',
      ),
      if (model.protected)
        (
          shortcut: 'x',
          label: 'Remove passphrase',
          view: TuiView.removePassphrase,
          description: 'Remove the passphrase. Keep platform protection.',
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
        description: 'Delete all saved keys and remove the passphrase.',
      ),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    _menu.currentIndex = _data ? 1 : 0;
    final actions = _categoryActions;
    return KeyBindings(
      bindings: [
        KeyBinding(KeyCode.escape, onTrigger: (_) => _open(TuiView.browse)),
        KeyBinding(KeyCode.s, onTrigger: (_) => _category(0)),
        KeyBinding(KeyCode.d, onTrigger: (_) => _category(1)),
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
            if (_contentFocus.hasFocus) {
              _menuFocus.requestFocus();
            } else {
              event.bubble();
            }
          },
        ),
        for (final action in actions)
          KeyBinding(
            KeyCode.char(action.shortcut),
            onTrigger: (_) => _open(action.view),
          ),
      ],
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          maxWidth: 100,
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
                          width: narrow ? 10 : 16,
                          height: 2,
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
                        Expanded(child: _content(actions, narrow: narrow)),
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
                          : _contentFocus.hasFocus
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
    );
  }

  Widget _categoryList() => FocusDetector(
    onFocusChange: (_) => setState(() {}),
    child: ListView.builder(
      controller: _menu,
      focusNode: _menuFocus,
      autofocus: model.view == TuiView.settings,
      itemCount: 2,
      onFocusedItemChanged: _category,
      onSelect: (_) => _contentFocus.requestFocus(),
      itemBuilder: (_, i, highlighted) => _row(
        label: i == 0 ? 'Security' : 'Data',
        current: highlighted,
        focused: highlighted && _menuFocus.hasFocus,
        active: i == (_data ? 1 : 0),
        hovered: _hoveredMenu == i,
        onHover: (value) => setState(() => _hoveredMenu = value ? i : null),
        onPressed: () {
          _category(i);
          _menuFocus.requestFocus();
        },
      ),
    ),
  );

  Widget _content(List<_SettingsAction> actions, {required bool narrow}) =>
      LayoutBuilder(
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
              Text(
                _data ? 'Data' : 'Security',
                style: const CellStyle(bold: true),
              ),
              const SizedBox(height: 1),
              if (!_data) ...[
                Text(
                  'Passphrase: ${model.protected ? 'On' : 'Off'}',
                  // Amber is Keybay's "note this" role, not its error role:
                  // platform-only is supported, but it is the weaker state and
                  // should not be the quieter of the two.
                  style: model.protected
                      ? context.accents.accent
                      : context.accents.attention,
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
