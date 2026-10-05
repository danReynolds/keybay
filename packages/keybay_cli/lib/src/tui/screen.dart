import 'dart:async';

import 'package:fleury/fleury_core.dart';
import 'package:fleury_widgets/fleury_widgets_web.dart'
    show ToastHandle, ToastSeverity, Toaster;

import 'chrome.dart';
import 'auth_views.dart';
import 'forms.dart';
import 'model.dart';
import 'settings.dart';
import 'vault.dart';

export 'chrome.dart';
export 'forms.dart';
export 'settings.dart';
export 'vault.dart';

/// One root and one current view. A view change unmounts secret fields instead
/// of retaining hidden routes/controllers in a navigator stack.
final class KeybayTui extends StatelessWidget {
  const KeybayTui({super.key, required this.model});
  final TuiModel model;

  /// Forms stay mounted below the minimum size so their masked drafts survive
  /// a resize; every other view is replaced by the prompt.
  static const _keepsDraft = {
    TuiView.unlock,
    TuiView.create,
    TuiView.edit,
    TuiView.passphrase,
    TuiView.reset,
    TuiView.hardware,
    TuiView.hardwareUnlock,
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: model,
    builder: (_, _) => Theme(
      data: keybayThemeFor(model.appearance),
      child: Toaster(
        maxToasts: 1,
        duration: tuiNoticeDuration,
        child: _MessagePresenter(model: model, child: _body()),
      ),
    ),
  );

  Widget _body() {
    return LayoutBuilder(
      builder: (context, size) {
        final minimumRows = (size.maxCols ?? 80) < 80 ? 24 : 20;
        final tooSmall =
            (size.maxCols ?? 80) < 40 || (size.maxRows ?? 24) < minimumRows;
        return FocusTraversalGroup(
          child: Center(
            child: ConstrainedBox(
              // Keep the whole app together in a large terminal. Smaller
              // windows retain the full space needed by forms and actions.
              maxWidth: 104,
              maxHeight: 32,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  vertical: (size.maxRows ?? 24) <= 24 ? 0 : 1,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _current(context, tooSmall)),
                    if (!tooSmall &&
                        model.showsBusy &&
                        model.view != TuiView.hardware &&
                        model.view != TuiView.hardwareUnlock)
                      BusyIndicator(
                        model: model,
                        compact: true,
                        label: model.view == TuiView.unlock
                            ? 'Unlocking'
                            : 'Working',
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _current(BuildContext context, bool tooSmall) {
    if (tooSmall && !_keepsDraft.contains(model.view)) {
      return ResizePrompt(model: model);
    }
    return switch (model.view) {
      TuiView.opening =>
        model.showsBusy
            ? _panel(
                context,
                'Opening Keybay',
                [const Text('The platform may ask you to authorize access.')],
                [_quit()],
              )
            : const SizedBox.shrink(),
      TuiView.closing => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Closing Keybay…'),
            if (model.busy)
              Text(
                'Submitted changes may complete after exit.',
                style: context.theme.mutedStyle,
              ),
          ],
        ),
      ),
      TuiView.unlock => UnlockForm(
        key: const ValueKey('unlock'),
        model: model,
        tooSmall: tooSmall,
      ),
      TuiView.methods ||
      TuiView.unlockMethods => AuthMethodsScreen(model: model),
      TuiView.hardware || TuiView.hardwareUnlock => HardwareForm(
        key: ValueKey(model.view),
        model: model,
        tooSmall: tooSmall,
      ),
      TuiView.removeMethod => _confirmation(
        context,
        'Remove this unlock method?',
        [
          Text(safeTuiLabel(model.selectedMethod?.label ?? ''), maxLines: 2),
          Text(
            model.methods.length == 1
                ? 'This leaves platform protection alone.'
                : 'One of the remaining unlock methods will still be required.',
          ),
          if (model.selectedMethod?.rpId != null)
            const Text('The passkey remains on its key or provider.'),
        ],
        action: 'Remove',
        confirm: model.removeSelectedMethod,
        cancel: TuiView.methods,
      ),
      TuiView.recovery => _panel(
        context,
        'Forgot your passphrase?',
        [
          const Text(
            "Your passphrase can't be recovered. You can reset Keybay to start over, but that deletes all saved keys.",
          ),
        ],
        [
          TuiAction(
            label: 'Back',
            shortcut: 'Esc',
            autofocus: true,
            onPressed: () => model.navigate(TuiView.unlock),
          ),
          TuiAction(
            label: 'Reset Keybay…',
            onPressed: () => model.navigate(TuiView.reset),
          ),
        ],
        backTo: TuiView.unlock,
      ),
      TuiView.create => RecordForm(
        key: const ValueKey('create'),
        model: model,
        replacing: false,
        tooSmall: tooSmall,
      ),
      TuiView.edit => RecordForm(
        key: const ValueKey('edit'),
        model: model,
        replacing: true,
        tooSmall: tooSmall,
      ),
      TuiView.passphrase => PassphraseForm(
        key: const ValueKey('passphrase'),
        model: model,
        tooSmall: tooSmall,
      ),
      TuiView.reset => ResetForm(
        key: const ValueKey('reset'),
        model: model,
        tooSmall: tooSmall,
      ),
      TuiView.browse => Vault(model: model),
      TuiView.firstUse => _panel(
        context,
        'Your Keybay store is ready',
        [
          const Text(
            'Platform protection is active. Add an unlock method to require a passphrase or hardware key when opening this store.',
          ),
        ],
        [
          _go(context, 'Add passphrase', TuiView.passphrase),
          if (model.supportsHardware)
            _go(context, 'Add hardware key', TuiView.hardware),
          _go(
            context,
            'Continue with platform protection',
            TuiView.browse,
            autofocus: true,
          ),
          _quit(),
        ],
      ),
      TuiView.settings ||
      TuiView.security ||
      TuiView.data ||
      TuiView.appearance => SettingsScreen(
        key: const ValueKey('settings'),
        model: model,
      ),
      TuiView.delete => _confirmation(
        context,
        'Delete this key?',
        [
          Text(safeTuiText(model.selectedKey ?? '')),
          const Text('This cannot be undone in Keybay.'),
        ],
        action: 'Delete key',
        confirm: model.deleteSelected,
        cancel: TuiView.browse,
      ),
      TuiView.clear => _confirmation(
        context,
        'Clear all records?',
        [
          const Text(
            'Delete every record. No undo in Keybay. Keep protection and this session.',
          ),
        ],
        action: 'Clear all records',
        confirm: model.clearRecords,
        cancel: TuiView.data,
      ),
      TuiView.removePassphrase => _confirmation(
        context,
        'Remove passphrase protection?',
        [
          const Text(
            'Removing the final unlock method leaves platform protection alone.',
          ),
        ],
        action: 'Remove passphrase',
        confirm: model.removePassphrase,
        cancel: TuiView.security,
      ),
      TuiView.failed => _panel(
        context,
        'Keybay needs your attention',
        [
          const Text(
            'The store was preserved. Reopen to authenticate its current state.',
          ),
        ],
        [
          _call(context, 'Reopen', model.open, autofocus: true),
          if (model.resetFromFailure)
            _go(context, 'Reset Keybay', TuiView.reset),
          _quit(),
        ],
      ),
    };
  }

  Widget _panel(
    BuildContext context,
    String title,
    List<Widget> body,
    List<TuiAction> actions, {
    TuiView? backTo,
  }) => KeyBindings(
    bindings: [
      KeyBinding(
        KeyCode.escape,
        onTrigger: (_) {
          if (backTo != null) {
            model.navigate(backTo);
          } else if (model.hasSession) {
            model.navigate(TuiView.browse);
          }
        },
      ),
    ],
    child: Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        maxWidth: 64,
        child: KeybayFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: model.view == TuiView.failed
                    ? context.accents.attention
                    : const CellStyle(bold: true),
              ),
              const SizedBox(height: 1),
              ...body,
              const SizedBox(height: 1),
              ActionGrid(actions: actions, maxColumns: 2),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _confirmation(
    BuildContext context,
    String title,
    List<Widget> body, {
    required String action,
    required Future<void> Function() confirm,
    required TuiView cancel,
  }) => KeyBindings(
    bindings: [
      KeyBinding(KeyCode.escape, onTrigger: (_) => model.navigate(cancel)),
    ],
    child: Center(
      child: ConstrainedBox(
        maxWidth: 64,
        child: Semantics(
          role: SemanticRole.dialog,
          label: title,
          actions: const {SemanticAction.dismiss},
          onAction: (_) => model.navigate(cancel),
          child: KeybayFrame(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: context.theme.errorStyle,
                  allowSelect: false,
                ),
                const SizedBox(height: 1),
                ...body,
                const SizedBox(height: 1),
                ActionGrid(
                  maxColumns: 2,
                  actions: [
                    TuiAction(
                      label: 'Cancel',
                      shortcut: 'Esc',
                      autofocus: true,
                      onPressed: () => model.navigate(cancel),
                    ),
                    _call(
                      context,
                      action,
                      confirm,
                      variant: ButtonVariant.error,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  TuiAction _go(
    BuildContext context,
    String label,
    TuiView view, {
    bool autofocus = false,
  }) => TuiAction(
    label: label,
    variant: switch (view) {
      TuiView.passphrase => ButtonVariant.primary,
      TuiView.clear ||
      TuiView.reset ||
      TuiView.removePassphrase => ButtonVariant.error,
      _ => ButtonVariant.normal,
    },
    autofocus: autofocus,
    onPressed: model.busy ? null : () => model.navigate(view),
  );

  TuiAction _call(
    BuildContext context,
    String label,
    Future<void> Function() call, {
    bool autofocus = false,
    ButtonVariant variant = ButtonVariant.normal,
  }) => TuiAction(
    label: label,
    variant: variant,
    autofocus: autofocus,
    onPressed: model.busy ? null : () => unawaited(call()),
  );

  TuiAction _quit() => TuiAction(
    label: 'Quit',
    autofocus: true,
    onPressed: () => unawaited(model.close()),
  );
}

/// Shows each model message once, as a toast. The model owns what the message
/// says; the toaster owns how long it stays.
final class _MessagePresenter extends StatefulWidget {
  const _MessagePresenter({required this.model, required this.child});
  final TuiModel model;
  final Widget child;
  @override
  State<_MessagePresenter> createState() => _MessagePresenterState();
}

final class _MessagePresenterState extends State<_MessagePresenter> {
  int _shown = -1;
  final _toastId = Object();
  ToastHandle? _toast;
  Object? _toastScope;
  bool _toastIsError = false;

  @override
  void initState() {
    super.initState();
    widget.model.addListener(_present);
  }

  @override
  void dispose() {
    widget.model.removeListener(_present);
    _toast?.dismiss();
    super.dispose();
  }

  void _present() {
    final model = widget.model;
    final revision = model.messageRevision;
    if (!mounted || revision == _shown) return;
    _shown = revision;
    TuiBinding.of(context).addPostFrameCallback((_) {
      if (!mounted || model.messageRevision != revision) return;
      if (model.status.isEmpty) {
        _toast?.dismiss();
        return;
      }
      // A different success is not an acknowledgement of a visible failure.
      // The handle also accounts for Escape and semantic dismissal by Fleury.
      if (_toast?.isActive == true &&
          _toastIsError &&
          !model.error &&
          _toastScope != model.messageScope) {
        return;
      }
      _toastScope = model.messageScope;
      _toastIsError = model.error;
      _toast = Toaster.show(
        context,
        model.status,
        id: _toastId,
        severity: model.error ? ToastSeverity.error : ToastSeverity.success,
        persistent: model.error,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // Also on build, so a message raised before this widget mounted — an
    // opening failure, say — is still presented once.
    _present();
    return widget.child;
  }
}
