import 'dart:async';

import 'package:fleury/fleury_core.dart';
import 'chrome.dart';
import 'model.dart';
import 'secret_draft.dart';

export 'secret_draft.dart';

/// Shared form shell: a centred 60-column body, its title, the action grid and
/// the accelerators that reach them. The body is sized against the same row
/// budget as the actions so they stay visible at the supported minimum.
final class FormShell extends StatelessWidget {
  const FormShell({
    super.key,
    required this.title,
    required this.actions,
    required this.body,
    this.titleStyle = const CellStyle(bold: true),
    this.subtitle,
    this.bindings = const [],
    this.footer,
  });

  final String title;
  final CellStyle titleStyle;
  final Widget? subtitle;
  final ActionGrid actions;
  final List<KeyBinding> bindings;
  final Widget? footer;

  /// Receives the resolved column and row budget plus the rows the action grid
  /// will occupy at that width.
  final List<Widget> Function(int cols, int rows, int actionRows) body;

  @override
  Widget build(BuildContext context) => KeyBindings(
    bindings: bindings,
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        maxWidth: 60,
        child: LayoutBuilder(
          builder: (_, size) {
            final cols = size.maxCols ?? 60;
            final rows = size.maxRows ?? 17;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title, allowSelect: false, style: titleStyle),
                if (subtitle != null) subtitle!,
                const SizedBox(height: 1),
                ...body(cols, rows, actions.rowsFor(cols)),
                actions,
                if (footer != null) footer!,
              ],
            );
          },
        ),
      ),
    ),
  );
}

/// Unlock an existing protected store. Cancelling closes the invocation
/// because there is no authenticated screen to return to.
final class UnlockForm extends StatefulWidget {
  const UnlockForm({super.key, required this.model, this.tooSmall = false});
  final TuiModel model;
  final bool tooSmall;
  @override
  State<UnlockForm> createState() => _UnlockFormState();
}

final class _UnlockFormState extends State<UnlockForm>
    with FormFields<UnlockForm>, SecretDrafts<UnlockForm> {
  final _phrase = SecretDraft.passphrase();
  String? _error;
  String? get _validationError => _error ?? model.unlockError;
  @override
  TuiModel get model => widget.model;
  @override
  List<SecretDraft> get drafts => [_phrase];

  @override
  void clearFieldErrors() {
    _error = null;
    model.clearUnlockError();
  }

  void _back() {
    eraseDrafts();
    unawaited(model.close());
  }

  Future<void> _submit() async {
    if (model.busy) return;
    final phrase = _phrase.takeBytes();
    eraseDrafts();
    if (phrase.isEmpty || phrase.length > 1024) {
      clearBytes(phrase);
      setState(() => _error = 'Enter 1–1024 UTF-8 bytes.');
      _phrase.focus.requestFocus();
      return;
    }
    await model.open(phrase);
    if (!mounted || model.view != TuiView.unlock || model.ending) return;
    // Disabling the field releases focus. Restore it after the enabled field
    // has rebuilt so a retry can be typed immediately, including after a click.
    TuiBinding.of(context).addPostFrameCallback((_) {
      if (mounted && model.view == TuiView.unlock && !model.busy) {
        _phrase.focus.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tooSmall) {
      revealed = false;
      return ResizePrompt(model: model, draft: true);
    }
    return FormShell(
      title: 'Unlock Keybay',
      bindings: [
        KeyBinding(KeyCode.escape, onTrigger: (_) => _back()),
        KeyBinding(KeySequence.ctrl.r, onTrigger: (_) => toggleReveal()),
      ],
      actions: ActionGrid(
        actions: [
          TuiAction(
            label: 'Unlock',
            shortcut: 'Enter',
            variant: ButtonVariant.success,
            onPressed: model.busy ? null : _submit,
          ),
          TuiAction(
            label: revealed ? 'Hide' : 'Reveal',
            shortcut: 'Ctrl+R',
            reservedLabel: 'Reveal',
            variant: ButtonVariant.warning,
            onPressed: model.busy ? null : toggleReveal,
          ),
          TuiAction(label: 'Cancel', shortcut: 'Esc', onPressed: _back),
        ],
      ),
      footer: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 1),
          Align(
            alignment: Alignment.topLeft,
            child: TuiAction(
              label: 'Forgot passphrase?',
              onPressed: model.busy
                  ? null
                  : () {
                      eraseDrafts();
                      model.navigate(TuiView.recovery);
                    },
            ),
          ),
        ],
      ),
      body: (cols, rows, actionRows) => [
        Text(
          'Passphrase${discloses(_phrase)}',
          style: revealed ? context.accents.attention : CellStyle.none,
        ),
        secretField(
          TextInput(
            controller: _phrase.controller,
            focusNode: _phrase.focus,
            semanticLabel: 'Passphrase',
            obscureText: !revealed,
            style: revealed ? context.accents.attention : CellStyle.none,
            clipboardPolicy: TextClipboardPolicy.redacted,
            autofocus: true,
            enabled: !model.busy,
            onChanged: (text) {
              setState(clearFieldErrors);
              checkSecret(_phrase, text);
            },
            validationError: _validationError,
            onSubmit: (_) => _submit(),
            onEscape: _back,
          ),
          draft: _phrase,
          invalid: _validationError != null,
        ),
        SizedBox(
          height: 2,
          child: Text(
            _validationError ?? '',
            style: context.theme.errorStyle,
            allowSelect: false,
          ),
        ),
      ],
    );
  }
}

/// New and Edit share one compact Key/Value form. Edit uses the key name as
/// its title and has no key input; renaming is outside scope.
final class RecordForm extends StatefulWidget {
  const RecordForm({
    super.key,
    required this.model,
    required this.replacing,
    this.tooSmall = false,
  });
  final TuiModel model;
  final bool replacing;
  final bool tooSmall;
  @override
  State<RecordForm> createState() => _RecordFormState();
}

final class _RecordFormState extends State<RecordForm>
    with FormFields<RecordForm>, SecretDrafts<RecordForm> {
  final _value = SecretDraft.record();
  late final _name = TextEditingController(
    editPolicy: keyTextPolicy,
    onEditRejected: (_) =>
        setState(() => _nameError = 'Use at most 120 ASCII characters.'),
  );
  final _nameFocus = FocusNode();
  String? _nameError;
  @override
  TuiModel get model => widget.model;
  @override
  List<SecretDraft> get drafts => [_value];
  bool get _replacing => widget.replacing;

  @override
  void initState() {
    super.initState();
    if (_replacing) {
      _name.text = model.selectedKey!;
      _value.controller.text = model.takeEditText();
    }
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _name.dispose();
    super.dispose();
  }

  void _back() {
    eraseDrafts();
    model.navigate(model.formReturnView);
  }

  @override
  void clearFieldErrors() => _nameError = null;

  void _checkName(String text) {
    if (_nameError != null) {
      setState(
        () => _nameError = model.recordNameError(text, replace: _replacing),
      );
    }
  }

  /// One validation path for advancing from Key and submitting the form.
  /// Reject before the value leaves the editor, preserving a correctable draft.
  bool _validateName() {
    final error = model.recordNameError(_name.text, replace: _replacing);
    setState(() {
      _nameError = error;
      if (error != null) revealed = false;
    });
    if (error != null) {
      _nameFocus.requestFocus();
      return false;
    }
    return true;
  }

  void _advanceToValue() {
    if (!model.busy && _validateName()) _value.focus.requestFocus();
  }

  void _submit() {
    if (model.busy || !_validateName()) return;
    final bytes = _value.takeBytes();
    eraseDrafts();
    unawaited(model.save(_name.text, bytes, replace: _replacing));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tooSmall) {
      revealed = false;
      return ResizePrompt(model: model, draft: true);
    }
    return FormShell(
      title: _replacing ? _name.text : 'New key',
      bindings: [
        KeyBinding(KeyCode.escape, onTrigger: (_) => _back()),
        KeyBinding(KeySequence.ctrl.s, onTrigger: (_) => _submit()),
        KeyBinding(KeySequence.ctrl.r, onTrigger: (_) => toggleReveal()),
      ],
      actions: ActionGrid(
        actions: [
          TuiAction(
            label: 'Save',
            shortcut: 'Ctrl+S',
            variant: ButtonVariant.success,
            onPressed: model.busy ? null : _submit,
          ),
          TuiAction(
            label: revealed ? 'Hide' : 'Reveal',
            shortcut: 'Ctrl+R',
            reservedLabel: 'Reveal',
            variant: ButtonVariant.warning,
            onPressed: model.busy ? null : toggleReveal,
          ),
          TuiAction(label: 'Cancel', shortcut: 'Esc', onPressed: _back),
        ],
      ),
      body: (cols, rows, actionRows) {
        // A wrapped key title and the action rows share the form's budget.
        final keyRows = (_name.text.length / cols).ceil().clamp(1, 4);
        final fixedRows = (_replacing ? 5 + keyRows : 11) + actionRows;
        final valueRows = (rows - fixedRows).clamp(1, 3);
        return [
          if (!_replacing) ...[
            const Text('Key'),
            field(
              TextInput(
                controller: _name,
                focusNode: _nameFocus,
                semanticLabel: 'Key name',
                validationError: _nameError,
                onChanged: _checkName,
                placeholder: 'e.g. openai',
                placeholderStyle: context.accents.placeholder,
                autofocus: true,
                enabled: !model.busy,
                clipboardPolicy: TextClipboardPolicy.disabled,
                onSubmit: (_) => _advanceToValue(),
                onEscape: _back,
              ),
              focus: _nameFocus,
              invalid: _nameError != null,
            ),
            SizedBox(
              height: 1,
              child: Text(
                _nameError ?? '',
                style: context.theme.errorStyle,
                maxLines: 1,
                allowSelect: false,
              ),
            ),
          ],
          Row(
            children: [
              Expanded(
                child: Text(
                  'Value${discloses(_value)}',
                  style: revealed ? context.accents.attention : CellStyle.none,
                ),
              ),
              if (_value.focus.hasFocus) ...[
                const SizedBox(width: 1),
                Text(
                  previewsEscaped(_value)
                      ? 'Ctrl+R edit'
                      : 'Alt+Enter new line',
                  style: context.theme.mutedStyle,
                  allowSelect: false,
                ),
              ],
            ],
          ),
          secretField(
            TextArea(
              controller: _value.controller,
              focusNode: _value.focus,
              semanticLabel: 'Secret value',
              obscureText: !revealed,
              style: revealed ? context.accents.attention : CellStyle.none,
              placeholder: 'Enter a value…',
              placeholderStyle: context.accents.placeholder,
              minLines: 1,
              maxLines: valueRows,
              keymap: TextEditingKeymap.chat,
              // Apply a received, in-limit paste as one edit before a resize
              // can unmount the input for the compact prompt.
              pastePolicy: const TextPastePolicy.immediate(),
              onSubmit: (_) => _submit(),
              clipboardPolicy: TextClipboardPolicy.redacted,
              autofocus: _replacing,
              enabled: !model.busy,
              onChanged: (text) => checkSecret(_value, text),
              onEscape: _back,
            ),
            draft: _value,
            rows: valueRows,
          ),
          const SizedBox(height: 1),
        ];
      },
    );
  }
}

/// Add or replace the store passphrase. Reveal covers both inputs together so
/// a mismatch can be inspected without toggling twice.
final class PassphraseForm extends StatefulWidget {
  const PassphraseForm({super.key, required this.model, this.tooSmall = false});
  final TuiModel model;
  final bool tooSmall;
  @override
  State<PassphraseForm> createState() => _PassphraseFormState();
}

final class _PassphraseFormState extends State<PassphraseForm>
    with FormFields<PassphraseForm>, SecretDrafts<PassphraseForm> {
  final _phrase = SecretDraft.passphrase();
  final _confirm = SecretDraft.passphrase();
  String? _phraseError;
  String? _confirmError;
  @override
  TuiModel get model => widget.model;
  @override
  List<SecretDraft> get drafts => [_phrase, _confirm];

  @override
  void clearFieldErrors() {
    _phraseError = null;
    _confirmError = null;
  }

  void _back() {
    eraseDrafts();
    model.navigate(model.formReturnView);
  }

  /// A missing or mismatched confirmation is local: keep both drafts, conceal
  /// them, and point at the field that needs correcting.
  bool _validate() {
    setState(() {
      _phraseError = _phrase.text.isEmpty ? 'Enter a passphrase.' : null;
      _confirmError = _confirm.text.isEmpty
          ? 'Confirm your passphrase.'
          : _phrase.text != _confirm.text
          ? "Passphrases don't match."
          : null;
    });
    return _phraseError == null && _confirmError == null;
  }

  void _revalidate(SecretDraft draft, String text) {
    checkSecret(draft, text);
    if (_phraseError != null || _confirmError != null) _validate();
  }

  void _submit() {
    if (model.busy) return;
    if (!_validate()) {
      setState(() => revealed = false);
      (_phraseError != null ? _phrase : _confirm).focus.requestFocus();
      return;
    }
    final phrase = _phrase.takeBytes();
    eraseDrafts();
    unawaited(model.changePassphrase(phrase));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tooSmall) {
      revealed = false;
      return ResizePrompt(model: model, draft: true);
    }
    return FormShell(
      title: model.protected ? 'Change passphrase' : 'Add passphrase',
      subtitle: const Text(
        'No recovery for a lost passphrase.',
        style: CellStyle(foreground: AnsiColor(3)),
        maxLines: 3,
      ),
      bindings: [
        KeyBinding(KeyCode.escape, onTrigger: (_) => _back()),
        KeyBinding(KeySequence.ctrl.s, onTrigger: (_) => _submit()),
        KeyBinding(KeySequence.ctrl.r, onTrigger: (_) => toggleReveal()),
      ],
      actions: ActionGrid(
        actions: [
          TuiAction(
            label: 'Save',
            shortcut: 'Ctrl+S',
            variant: ButtonVariant.success,
            onPressed: model.busy ? null : _submit,
          ),
          TuiAction(
            label: revealed ? 'Hide' : 'Reveal',
            shortcut: 'Ctrl+R',
            reservedLabel: 'Reveal',
            variant: ButtonVariant.warning,
            onPressed: model.busy ? null : toggleReveal,
          ),
          TuiAction(label: 'Cancel', shortcut: 'Esc', onPressed: _back),
        ],
      ),
      body: (cols, rows, actionRows) => [
        Text(
          'Passphrase${discloses(_phrase)}',
          style: revealed ? context.accents.attention : CellStyle.none,
        ),
        secretField(
          TextInput(
            controller: _phrase.controller,
            focusNode: _phrase.focus,
            semanticLabel: 'Passphrase',
            obscureText: !revealed,
            style: revealed ? context.accents.attention : CellStyle.none,
            clipboardPolicy: TextClipboardPolicy.redacted,
            autofocus: true,
            enabled: !model.busy,
            onChanged: (text) => _revalidate(_phrase, text),
            validationError: _phraseError,
            onSubmit: (_) => _confirm.focus.requestFocus(),
            onEscape: _back,
          ),
          draft: _phrase,
          invalid: _phraseError != null,
        ),
        if (_phraseError != null)
          Text(
            _phraseError!,
            style: context.theme.errorStyle,
            allowSelect: false,
          ),
        // Separate the two field groups when the terminal has the height.
        if (rows > 12 + actionRows) const SizedBox(height: 1),
        Text(
          'Confirm passphrase${discloses(_confirm)}',
          style: revealed ? context.accents.attention : CellStyle.none,
        ),
        secretField(
          TextInput(
            controller: _confirm.controller,
            focusNode: _confirm.focus,
            semanticLabel: 'Confirm passphrase',
            obscureText: !revealed,
            style: revealed ? context.accents.attention : CellStyle.none,
            clipboardPolicy: TextClipboardPolicy.redacted,
            enabled: !model.busy,
            onChanged: (text) => _revalidate(_confirm, text),
            validationError: _confirmError,
            onSubmit: (_) => _submit(),
            onEscape: _back,
          ),
          draft: _confirm,
          invalid: _confirmError != null,
        ),
        if (_phraseError == null)
          SizedBox(
            height: 1,
            child: Text(
              _confirmError ?? '',
              style: context.theme.errorStyle,
              allowSelect: false,
            ),
          ),
      ],
    );
  }
}

/// Delete every value and protection method behind a typed confirmation. The
/// phrase is not a secret, so this form has no draft and no Reveal.
final class ResetForm extends StatefulWidget {
  const ResetForm({super.key, required this.model, this.tooSmall = false});
  final TuiModel model;
  final bool tooSmall;
  @override
  State<ResetForm> createState() => _ResetFormState();
}

final class _ResetFormState extends State<ResetForm>
    with FormFields<ResetForm> {
  late final _typed = TextEditingController(
    editPolicy: keyTextPolicy,
    onEditRejected: (_) =>
        setState(() => _error = 'Use up to 120 ASCII characters.'),
  );
  final _typedFocus = FocusNode();
  String? _error;
  TuiModel get model => widget.model;

  @override
  void dispose() {
    _typed.value = TextEditingValue.empty();
    _typed.dispose();
    _typedFocus.dispose();
    super.dispose();
  }

  void _back() => model.navigate(model.formReturnView);

  void _check(String text) {
    setState(() {
      _error = null;
    });
  }

  void _submit() {
    if (model.busy) return;
    if (_typed.text != resetConfirmation) {
      setState(() => _error = 'Type $resetConfirmation to confirm.');
      _typedFocus.requestFocus();
      return;
    }
    unawaited(model.reset(_typed.text));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tooSmall) return ResizePrompt(model: model, draft: true);
    return FormShell(
      title: 'Reset Keybay?',
      titleStyle: context.theme.errorStyle,
      bindings: [KeyBinding(KeyCode.escape, onTrigger: (_) => _back())],
      actions: ActionGrid(
        actions: [
          TuiAction(
            label: 'Reset Keybay',
            variant: ButtonVariant.error,
            onPressed: model.busy || _typed.text != resetConfirmation
                ? null
                : _submit,
          ),
          TuiAction(label: 'Cancel', shortcut: 'Esc', onPressed: _back),
        ],
      ),
      body: (cols, rows, actionRows) => [
        const Text(
          'All saved keys will be deleted and your passphrase removed.',
          maxLines: 3,
        ),
        const Text("This can't be undone."),
        const SizedBox(height: 1),
        const Text('Type $resetConfirmation to confirm:', maxLines: 2),
        field(
          TextInput(
            controller: _typed,
            focusNode: _typedFocus,
            semanticLabel: 'Reset confirmation',
            validationError: _error,
            onChanged: _check,
            autofocus: true,
            enabled: !model.busy,
            onSubmit: (_) => _submit(),
            clipboardPolicy: TextClipboardPolicy.disabled,
          ),
          focus: _typedFocus,
          invalid: _error != null,
        ),
        SizedBox(
          height: 1,
          child: Text(
            _error ?? '',
            style: context.theme.errorStyle,
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}
