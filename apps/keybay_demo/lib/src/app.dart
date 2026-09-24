import 'dart:async';

import 'package:flutter/material.dart';
import 'package:keybay/keybay.dart';

import 'vault.dart';
import 'vault_backend.dart';

class KeybayDemoApp extends StatefulWidget {
  const KeybayDemoApp({super.key, required this.backend});

  final VaultBackend backend;

  @override
  State<KeybayDemoApp> createState() => _KeybayDemoAppState();
}

class _KeybayDemoAppState extends State<KeybayDemoApp>
    with WidgetsBindingObserver {
  final _routes = _RouteTracker();
  late final Vault _vault = Vault(widget.backend);
  var _covered = false;
  var _closedInBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _vault.addListener(_dismissWhenClosed);
    unawaited(_vault.open());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Cover the window whenever the app is not in front, so a revealed value
    // never reaches the app switcher's snapshot. Leaving the foreground closes
    // the session; returning opens it again, asking for the passphrase if set.
    setState(() => _covered = state != AppLifecycleState.resumed);
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      if (_vault.stage == VaultStage.open ||
          _vault.stage == VaultStage.locked) {
        _closedInBackground = true;
        unawaited(_vault.close());
      }
    } else if (state == AppLifecycleState.resumed && _closedInBackground) {
      _closedInBackground = false;
      unawaited(_vault.open());
    }
  }

  void _dismissWhenClosed() {
    // Sheets and dialogs can show a revealed value; none outlives the session.
    if (_vault.stage != VaultStage.open) _routes.removeAboveFirst();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _vault.removeListener(_dismissWhenClosed);
    _vault.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Keybay Demo',
    navigatorObservers: [_routes],
    theme: ThemeData(colorSchemeSeed: Colors.teal),
    darkTheme: ThemeData(
      colorSchemeSeed: Colors.teal,
      brightness: Brightness.dark,
    ),
    builder: (context, child) => Stack(
      children: [
        child!,
        if (_covered)
          const Positioned.fill(child: ColoredBox(color: Colors.black)),
      ],
    ),
    home: ListenableBuilder(
      listenable: _vault,
      builder: (context, _) => switch (_vault.stage) {
        VaultStage.opening => const _Opening(),
        VaultStage.open => _VaultView(vault: _vault),
        VaultStage.locked => _UnlockView(vault: _vault),
        VaultStage.closed => _ClosedView(vault: _vault),
        VaultStage.failed => _FailedView(vault: _vault),
      },
    ),
  );
}

/// Tracks the routes above the home screen so they can all be removed at once.
final class _RouteTracker extends NavigatorObserver {
  final _routes = <Route<dynamic>>[];

  /// Removes every sheet and dialog without a closing animation. Frames stop
  /// while the app is in the background, so an animated pop would leave a
  /// revealed value on screen until the app returns.
  void removeAboveFirst() {
    final navigator = this.navigator;
    if (navigator == null) return;
    for (final route in _routes.reversed.toList()) {
      if (!route.isFirst) navigator.removeRoute(route);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.add(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _routes.remove(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _routes.remove(oldRoute);
    if (newRoute != null) _routes.add(newRoute);
  }
}

class _Opening extends StatelessWidget {
  const _Opening();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(child: CircularProgressIndicator(semanticsLabel: 'Opening')),
  );
}

class _ClosedView extends StatelessWidget {
  const _ClosedView({required this.vault});

  final Vault vault;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_outline, size: 48),
          const SizedBox(height: 12),
          const Text('The vault is closed.'),
          const SizedBox(height: 16),
          FilledButton(onPressed: vault.open, child: const Text('Open')),
        ],
      ),
    ),
  );
}

class _UnlockView extends StatefulWidget {
  const _UnlockView({required this.vault});

  final Vault vault;

  @override
  State<_UnlockView> createState() => _UnlockViewState();
}

class _UnlockViewState extends State<_UnlockView> {
  final _passphrase = TextEditingController();
  var _busy = false;

  Future<void> _unlock() async {
    if (_busy || _passphrase.text.isEmpty) return;
    setState(() => _busy = true);
    final text = _passphrase.text;
    _passphrase.clear();
    await widget.vault.unlock(text);
    if (mounted) setState(() => _busy = false);
  }

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.password, size: 48),
              const SizedBox(height: 12),
              Text(
                'Enter your passphrase',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passphrase,
                obscureText: true,
                autofocus: true,
                enabled: !_busy,
                decoration: InputDecoration(
                  labelText: 'Passphrase',
                  errorText: widget.vault.message,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _unlock(),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _unlock,
                child: const Text('Unlock'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _confirmReset(context, widget.vault),
                child: const Text('Forgot it? Reset the store'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _FailedView extends StatelessWidget {
  const _FailedView({required this.vault});

  final Vault vault;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(
              vault.message ?? 'The store could not be opened.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: vault.open, child: const Text('Try again')),
            TextButton(
              onPressed: () => _confirmReset(context, vault),
              child: const Text('Reset the store'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _VaultView extends StatelessWidget {
  const _VaultView({required this.vault});

  final Vault vault;

  @override
  Widget build(BuildContext context) {
    final keys = vault.keys;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Keybay Demo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Lock',
            onPressed: vault.close,
          ),
          IconButton(
            icon: const Icon(Icons.shield_outlined),
            tooltip: 'Protection',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              isScrollControlled: true,
              builder: (_) => _ProtectionSheet(vault: vault),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          ListTile(
            leading: Icon(
              vault.passphraseProtected ? Icons.password : Icons.shield,
            ),
            title: Text(
              vault.passphraseProtected
                  ? 'Passphrase and device protection'
                  : 'Device protection only',
            ),
            subtitle: Text(
              vault.createdNewStore
                  ? 'A new store was created on this device.'
                  : '${keys.length} saved',
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: keys.isEmpty
                ? const Center(child: Text('No secrets yet. Tap + to add one.'))
                : ListView.separated(
                    itemCount: keys.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) => ListTile(
                      leading: const Icon(Icons.key),
                      title: Text(keys[index]),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => showModalBottomSheet<void>(
                        context: context,
                        showDragHandle: true,
                        isScrollControlled: true,
                        builder: (_) =>
                            _SecretSheet(vault: vault, name: keys[index]),
                      ),
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add secret',
        onPressed: () => _editRecord(context, vault),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _SecretSheet extends StatefulWidget {
  const _SecretSheet({required this.vault, required this.name});

  final Vault vault;
  final String name;

  @override
  State<_SecretSheet> createState() => _SecretSheetState();
}

class _SecretSheetState extends State<_SecretSheet> {
  String? _value;

  /// The saved value, '' if it is gone, or null if it could not be read.
  Future<String?> _read() =>
      _guard(context, () async => await widget.vault.read(widget.name) ?? '');

  Future<void> _reveal() async {
    final value = await _read();
    if (mounted && value != null) setState(() => _value = value);
  }

  Future<void> _edit() async {
    final current = _value ?? await _read();
    if (!mounted || current == null) return;
    // The editor opens from the navigator: this sheet closes first.
    final navigator = Navigator.of(context)..pop();
    await _editRecord(
      navigator.context,
      widget.vault,
      name: widget.name,
      value: current,
    );
  }

  Future<void> _delete() async {
    final confirmed = await _confirm(
      context,
      title: 'Delete ${widget.name}?',
      action: 'Delete',
    );
    if (!confirmed || !mounted) return;
    final navigator = Navigator.of(context);
    await _guard(context, () => widget.vault.remove(widget.name));
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              value ?? '••••••••',
              key: const ValueKey('secret-value'),
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              if (value == null)
                FilledButton.tonal(
                  onPressed: _reveal,
                  child: const Text('Reveal'),
                )
              else
                FilledButton.tonal(
                  onPressed: () => setState(() => _value = null),
                  child: const Text('Hide'),
                ),
              OutlinedButton(onPressed: _edit, child: const Text('Edit')),
              TextButton(onPressed: _delete, child: const Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProtectionSheet extends StatelessWidget {
  const _ProtectionSheet({required this.vault});

  final Vault vault;

  Future<void> _setPassphrase(BuildContext context) async {
    final navigator = Navigator.of(context);
    final passphrase = await showDialog<String>(
      context: context,
      builder: (_) => _PassphraseDialog(changing: vault.passphraseProtected),
    );
    if (passphrase == null || !context.mounted) return;
    final changing = vault.passphraseProtected;
    await _guard(
      context,
      () => vault.setPassphrase(passphrase),
      done: changing ? 'Passphrase changed.' : 'Passphrase added.',
    );
    navigator.pop();
  }

  Future<void> _removePassphrase(BuildContext context) async {
    final navigator = Navigator.of(context);
    final confirmed = await _confirm(
      context,
      title: 'Remove the passphrase?',
      body:
          'Any program running as this app can then open the store with '
          'device protection alone.',
      action: 'Remove',
    );
    if (!confirmed || !context.mounted) return;
    await _guard(context, vault.removePassphrase, done: 'Passphrase removed.');
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            leading: Icon(Icons.shield),
            title: Text('Device keystore'),
            subtitle: Text(
              'Always on: the store key is sealed by this device.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.password),
            title: const Text('Passphrase'),
            subtitle: Text(
              vault.passphraseProtected
                  ? 'On: needed to open the store.'
                  : 'Off.',
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.edit),
            title: Text(
              vault.passphraseProtected
                  ? 'Change passphrase'
                  : 'Add passphrase',
            ),
            onTap: () => _setPassphrase(context),
          ),
          if (vault.passphraseProtected)
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: const Text('Remove passphrase'),
              onTap: () => _removePassphrase(context),
            ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Lock now'),
            onTap: vault.close,
          ),
          ListTile(
            leading: Icon(
              Icons.delete_forever,
              color: Theme.of(context).colorScheme.error,
            ),
            title: const Text('Reset store'),
            onTap: () => _confirmReset(context, vault),
          ),
        ],
      ),
    ),
  );
}

class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog({required this.changing});

  final bool changing;

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  String? _error;

  void _submit() {
    if (_first.text.isEmpty) {
      setState(() => _error = 'Enter a passphrase.');
    } else if (_first.text != _second.text) {
      setState(() => _error = 'The passphrases do not match.');
    } else {
      Navigator.of(context).pop(_first.text);
    }
  }

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.changing ? 'Change passphrase' : 'Add passphrase'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _first,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New passphrase'),
        ),
        TextField(
          controller: _second,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Repeat passphrase',
            errorText: _error,
          ),
          onSubmitted: (_) => _submit(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Save')),
    ],
  );
}

class _RecordEditor extends StatefulWidget {
  const _RecordEditor({required this.vault, this.name, this.value});

  final Vault vault;
  final String? name;
  final String? value;

  @override
  State<_RecordEditor> createState() => _RecordEditorState();
}

class _RecordEditorState extends State<_RecordEditor> {
  late final _name = TextEditingController(text: widget.name);
  late final _value = TextEditingController(text: widget.value);
  var _visible = false;
  var _busy = false;
  String? _error;

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.vault.save(name, _value.text);
      if (mounted) Navigator.of(context).pop();
    } on KeybayException catch (error) {
      if (mounted) setState(() => _error = describe(error.code));
    } on StateError catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.name != null;
    final replaces = !editing && widget.vault.keys.contains(_name.text.trim());
    return AlertDialog(
      title: Text(editing ? 'Edit secret' : 'Add secret'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            enabled: !editing && !_busy,
            autofocus: !editing,
            decoration: InputDecoration(
              labelText: 'Name',
              helperText: replaces
                  ? 'Saving replaces the existing value.'
                  : null,
            ),
            onChanged: (_) => setState(() => _error = null),
          ),
          TextField(
            controller: _value,
            enabled: !_busy,
            autofocus: editing,
            obscureText: !_visible,
            decoration: InputDecoration(
              labelText: 'Value',
              errorText: _error,
              suffixIcon: IconButton(
                icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
                tooltip: _visible ? 'Hide value' : 'Show value',
                onPressed: () => setState(() => _visible = !_visible),
              ),
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

Future<void> _editRecord(
  BuildContext context,
  Vault vault, {
  String? name,
  String? value,
}) => showDialog<void>(
  context: context,
  builder: (_) => _RecordEditor(vault: vault, name: name, value: value),
);

Future<void> _confirmReset(BuildContext context, Vault vault) async {
  final confirmed = await _confirm(
    context,
    title: 'Reset the store?',
    body:
        'This permanently deletes every secret in this app and its device '
        'key. It cannot be undone.',
    action: 'Reset',
  );
  if (confirmed) await vault.reset();
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  String? body,
  required String action,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: body == null ? null : Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

/// Runs [action], reporting a Keybay failure in a snack bar.
Future<T?> _guard<T>(
  BuildContext context,
  Future<T> Function() action, {
  String? done,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final result = await action();
    if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
    return result;
  } on KeybayException catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(describe(error.code))));
  } on StateError catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error.message)));
  }
  return null;
}
