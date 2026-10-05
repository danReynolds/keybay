import 'dart:async';
import 'dart:convert';

import 'package:fleury/fleury_core.dart';

import '../display_safety.dart';
import 'chrome.dart';
import 'forms.dart';
import 'model.dart';
import 'store.dart';

bool _labelPoint(int point) => point != 10 && !mustEscapeRune(point);

String methodKind(TuiAuthMethod method) => switch (method.kind) {
  TuiAuthKind.passphrase => 'Passphrase',
  TuiAuthKind.hardware => 'Hardware key',
  TuiAuthKind.system => 'System passkey · unavailable here',
};

/// The same bounded list selects an unlock enrollment or one to remove.
final class AuthMethodsScreen extends StatefulWidget {
  const AuthMethodsScreen({super.key, required this.model});
  final TuiModel model;
  @override
  State<AuthMethodsScreen> createState() => _AuthMethodsScreenState();
}

final class _AuthMethodsScreenState extends State<AuthMethodsScreen> {
  final _list = ListController(initialIndex: 0);
  final _focus = FocusNode();
  TuiModel get model => widget.model;
  bool get unlocking => !model.hasSession;
  List<TuiAuthMethod> get methods =>
      unlocking ? model.unlockMethods : model.methods;
  TuiAuthMethod? get current => methods.isEmpty
      ? null
      : methods[(_list.currentIndex ?? 0).clamp(0, methods.length - 1)];
  void _back() {
    if (unlocking) {
      unawaited(model.close());
    } else {
      model.navigate(TuiView.security);
    }
  }

  void _choose() {
    final method = current;
    if (method == null || model.busy) return;
    if (unlocking) {
      unawaited(model.chooseUnlock(method));
    } else {
      model.selectMethod(method);
      model.navigate(TuiView.removeMethod);
    }
  }

  @override
  void dispose() {
    _list.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => KeyBindings(
    bindings: [KeyBinding(KeyCode.escape, onTrigger: (_) => _back())],
    child: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        maxWidth: 64,
        child: KeybayFrame(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                unlocking ? 'Choose an unlock method' : 'Unlock methods',
                style: const CellStyle(bold: true),
              ),
              const SizedBox(height: 1),
              Expanded(
                child: methods.isEmpty
                    ? const Text('No additional unlock methods.')
                    : ListView.builder(
                        controller: _list,
                        focusNode: _focus,
                        autofocus: true,
                        itemCount: methods.length,
                        onFocusedItemChanged: (_) => setState(() {}),
                        onSelect: (_) => _choose(),
                        itemBuilder: (_, index, highlighted) => Text(
                          '${highlighted ? '›' : ' '} ${safeTuiLabel(methods[index].label)}',
                          maxLines: 1,
                          style: highlighted
                              ? context.theme.selectionStyle
                              : context.theme.textStyle,
                        ),
                      ),
              ),
              if (current case final method?) ...[
                Text(
                  '${methodKind(method)} · ${method.id.substring(0, method.id.length.clamp(0, 8))}',
                  maxLines: 2,
                ),
                if (method.rpId != null)
                  Text(
                    safeTuiText(method.rpId!),
                    maxLines: 2,
                    style: context.theme.mutedStyle,
                  ),
              ],
              const SizedBox(height: 1),
              ActionGrid(
                actions: [
                  TuiAction(
                    label: unlocking ? 'Unlock' : 'Remove…',
                    shortcut: 'Enter',
                    onPressed:
                        model.busy ||
                            current == null ||
                            unlocking && current!.kind == TuiAuthKind.system
                        ? null
                        : _choose,
                  ),
                  TuiAction(
                    label: unlocking ? 'Quit' : 'Back',
                    shortcut: 'Esc',
                    onPressed: _back,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// One form persists across the no-PIN attempt and a deliberate PIN submission.
/// It holds no credential material while native work is pending.
final class HardwareForm extends StatefulWidget {
  const HardwareForm({super.key, required this.model, this.tooSmall = false});
  final TuiModel model;
  final bool tooSmall;
  @override
  State<HardwareForm> createState() => _HardwareFormState();
}

final class _HardwareFormState extends State<HardwareForm>
    with FormFields<HardwareForm> {
  final _pin = SecretDraft(limit: 63, allowNewlines: false, allowNul: false);
  final _label = TextEditingController(
    editPolicy: const TextEditPolicy(
      maxCodeUnits: 256,
      allowCodePoint: _labelPoint,
    ),
  );
  final _labelFocus = FocusNode();
  final _submitFocus = FocusNode();
  String? _validation;
  bool _wasBusy = false;
  TuiModel get model => widget.model;
  bool get enrolling => model.view == TuiView.hardware;

  @override
  void initState() {
    super.initState();
    _wasBusy = model.busy;
    model.addListener(_changed);
  }

  void _changed() {
    final finished = _wasBusy && !model.busy;
    _wasBusy = model.busy;
    if (!finished || model.ending || !model.hardwareCanRetry) return;
    TuiBinding.of(context).addPostFrameCallback((_) {
      if (!mounted || model.busy || model.ending) return;
      if (model.hardwareNeedsPin) {
        _pin.focus.requestFocus();
      } else if (!enrolling && model.hardwareError != null) {
        _submitFocus.requestFocus();
      }
    });
  }

  void _back() {
    _pin.erase();
    unawaited(model.cancelHardware());
  }

  Future<void> _submit() async {
    if (model.busy || !model.hardwareCanRetry) return;
    final label = _label.text.trim().isEmpty
        ? 'Hardware key'
        : _label.text.trim();
    if (utf8.encode(label).length > 256) {
      setState(() => _validation = 'Use a name of at most 256 UTF-8 bytes.');
      return;
    }
    final pin = model.hardwareNeedsPin ? _pin.takeBytes() : null;
    _pin.erase();
    if (pin != null && (pin.length < 4 || pin.length > 63 || pin.contains(0))) {
      clearBytes(pin);
      setState(
        () => _validation = 'Enter the existing PIN (4–63 UTF-8 bytes).',
      );
      _pin.focus.requestFocus();
      return;
    }
    setState(() => _validation = null);
    await model.hardwareAttempt(label: label, pin: pin);
    if (!mounted || model.ending) return;
    TuiBinding.of(context).addPostFrameCallback((_) {
      if (mounted && !model.busy && model.hardwareCanRetry) {
        if (model.hardwareNeedsPin) {
          _pin.focus.requestFocus();
        } else if (!enrolling) {
          _submitFocus.requestFocus();
        }
      }
    });
  }

  @override
  void dispose() {
    model.removeListener(_changed);
    _pin.dispose();
    _label.dispose();
    _labelFocus.dispose();
    _submitFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tooSmall) return ResizePrompt(model: model, draft: true);
    final waiting = model.busy;
    return FormShell(
      title: enrolling ? 'Add hardware key' : 'Unlock Keybay',
      bindings: [KeyBinding(KeyCode.escape, onTrigger: (_) => _back())],
      actions: ActionGrid(
        actions: [
          if (enrolling ||
              !waiting &&
                  (model.hardwareNeedsPin || model.hardwareError != null))
            TuiAction(
              label: enrolling
                  ? 'Add'
                  : model.hardwareNeedsPin
                  ? 'Continue'
                  : 'Try again',
              shortcut: 'Enter',
              variant: ButtonVariant.primary,
              focusNode: _submitFocus,
              autofocus: !enrolling && !model.hardwareNeedsPin,
              onPressed: waiting || !model.hardwareCanRetry ? null : _submit,
            ),
          TuiAction(
            label: model.cancellingHardware
                ? 'Cancelling…'
                : enrolling
                ? 'Cancel'
                : model.canChooseAnotherMethod
                ? 'Other methods'
                : 'Quit',
            shortcut: 'Esc',
            autofocus: !enrolling && waiting,
            onPressed: model.cancellingHardware ? null : _back,
          ),
        ],
      ),
      body: (cols, rows, actionRows) => [
        if (!enrolling) ...[
          Text(safeTuiLabel(model.hardwareLabel), maxLines: 1),
          const SizedBox(height: 1),
        ],
        if (waiting) ...[
          Text(
            model.cancellingHardware
                ? 'Waiting for the key to stop…'
                : switch (model.hardwarePhase) {
                    HardwarePhase.checking => 'Checking for a hardware key…',
                    HardwarePhase.connecting => 'Connect your hardware key.',
                    HardwarePhase.verifying =>
                      'Touch your key when it flashes.',
                  },
            style: context.accents.attention,
          ),
          if (enrolling) const Text('Setup may ask more than once.'),
        ] else ...[
          if (enrolling && !model.hardwareNeedsPin) ...[
            const Text('Name (optional)'),
            field(
              TextInput(
                controller: _label,
                focusNode: _labelFocus,
                autofocus: true,
                semanticLabel: 'Hardware key name',
                onSubmit: (_) => _submit(),
                onEscape: _back,
              ),
              focus: _labelFocus,
            ),
          ],
          if (model.hardwareNeedsPin) ...[
            const Text('Hardware key PIN'),
            field(
              TextInput(
                controller: _pin.controller,
                focusNode: _pin.focus,
                autofocus: true,
                semanticLabel: 'Hardware key PIN',
                obscureText: true,
                clipboardPolicy: TextClipboardPolicy.redacted,
                enabled: model.hardwareCanRetry,
                onChanged: (value) {
                  if (!_pin.accepts(value)) {
                    _pin.erase();
                    setState(
                      () => _validation =
                          'PIN discarded: at most 63 UTF-8 bytes, no NUL.',
                    );
                  } else if (_validation != null) {
                    setState(() => _validation = null);
                  }
                },
                onSubmit: (_) => _submit(),
                onEscape: _back,
              ),
              focus: _pin.focus,
              invalid: _validation != null,
            ),
          ],
          if (model.hardwareNeedsPin || enrolling)
            Text(
              model.hardwareNeedsPin
                  ? 'Use your key’s existing PIN.'
                  : 'Connect one hardware key. Touch it when it flashes.',
              maxLines: 2,
            ),
        ],
        const SizedBox(height: 1),
        SizedBox(
          height: (rows - actionRows - (model.hardwareNeedsPin ? 9 : 8)).clamp(
            2,
            5,
          ),
          child: Text(
            _validation ?? model.hardwareError ?? '',
            style: context.theme.errorStyle,
            allowSelect: false,
          ),
        ),
      ],
    );
  }
}
