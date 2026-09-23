import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:characters/characters.dart';
import 'package:fleury/fleury_core.dart';
import '../display_safety.dart';
import '../key.dart';
import 'clipboard_contract.dart' show TuiCopyException;
import 'store.dart';

enum TuiView {
  opening,
  unlock,
  recovery,
  firstUse,
  browse,
  create,
  edit,
  delete,
  settings,
  security,
  data,
  passphrase,
  removePassphrase,
  clear,
  reset,
  failed,
  closing,
}

enum _RecordAction { reveal, edit, copy }

const resetConfirmation = 'RESET';
const tuiIdleTimeout = Duration(minutes: 5);
const tuiNoticeDuration = Duration(seconds: 3);

/// How long before the idle exit the warning appears. Long enough to react,
/// short enough that it is not standing advice.
const tuiIdleWarning = Duration(seconds: 30);

/// An operation must be this slow before it is worth telling the user about.
/// A local write settles well inside this, so the ordinary path shows nothing
/// rather than flashing a notice on every save.
const tuiBusyDelay = Duration(milliseconds: 150);

/// Presentation state and one invocation-owned storage session. Widgets never own
/// sessions or initiate background reads. A dismissed read must match _intent
/// before it may disclose its result; submitted mutations are always awaited.
final class TuiModel extends ChangeNotifier {
  TuiModel({
    required this.openSession,
    required this.resetStore,
    required this.authorize,
    this.copyText,
    required this.onExit,
    this.idleTimeout = tuiIdleTimeout,
  });

  final TuiSessionOpener openSession;
  final Future<void> Function() resetStore;
  final void Function() authorize;
  final Future<void> Function(String)? copyText;
  final void Function() onExit;

  /// The host's idle-exit policy, for display. Null means it is disabled.
  /// The native runner owns enforcement; the annotation preview has no timer.
  final Duration? idleTimeout;
  TuiSession? _session;
  String? _passphrase;
  Uint8List? _value;
  String? _valueText;
  int? _valueDisplayWidth;
  Future<void>? _pending;
  Future<void>? _closing;
  Timer? _busyTimer;
  bool _showsBusy = false;
  int _intent = 0;
  int concealRevision = 0;
  TuiView formReturnView = TuiView.browse;
  bool _ending = false;
  TuiView view = TuiView.opening;
  List<String> keys = const [];
  String? selectedKey;
  String query = '';
  String status = '';
  bool error = false;
  bool resetFromFailure = false;

  /// Authentication feedback belongs to the unlock field, not a global toast.
  String? unlockError;
  int exitCode = 0;

  bool get busy => _pending != null;

  /// Whether an operation has been pending long enough to be worth announcing.
  bool get showsBusy => _showsBusy;
  bool get protected => _passphrase != null;
  bool get hasSession => _session != null;
  bool get revealed => view == TuiView.browse && _value != null;
  bool get ending => _ending;

  /// Increments on every message so the presenter can tell a new one from a
  /// rebuild. Expiry belongs to the toast, not to the model.
  int messageRevision = 0;

  /// Identifies the action a result belongs to, so a successful retry can
  /// replace its failure without unrelated feedback hiding that failure.
  Object? messageScope;
  Object? _operationScope;

  /// Decode once per disclosure. Re-decoding on every read would rebuild the
  /// whole record and leave another plaintext copy on the heap each frame.
  String get valueText =>
      _value == null ? '' : (_valueText ??= utf8.decode(_value!));

  /// Cache display measurement with the disclosure, so views need not retain
  /// a plaintext reference merely to recognize the last measured value.
  int get valueDisplayWidth => _value == null
      ? 0
      : (_valueDisplayWidth ??= longestEscapedLine(valueText));

  List<String> get visibleKeys => keys
      .where((key) => key.toLowerCase().contains(query.toLowerCase()))
      .toList();

  void _clearValue() {
    _value?.fillRange(0, _value!.length, 0);
    _value = null;
    _valueText = null;
    _valueDisplayWidth = null;
  }

  void _clearStatus() {
    if (status.isEmpty) return;
    status = '';
    error = false;
    messageRevision++;
  }

  void message(String text, {bool failure = false, Object? scope}) {
    if (_ending) return;
    status = text;
    error = failure;
    messageScope = scope ?? _operationScope ?? view;
    messageRevision++;
    notifyListeners();
  }

  void hide() {
    _intent++;
    _clearValue();
    if (!_ending) notifyListeners();
  }

  /// Conceal on terminal blur/resize without cancelling an accepted form save.
  /// The active form retains its own masked controllers; no draft lives here.
  void conceal() {
    concealRevision++;
    if (view == TuiView.browse) {
      hide();
    } else if (!_ending) {
      notifyListeners();
    }
  }

  void search(String text) {
    if (_ending) return;
    hide();
    query = text;
    final matches = visibleKeys;
    if (!matches.contains(selectedKey)) selectedKey = matches.firstOrNull;
    notifyListeners();
  }

  void select(String key) {
    if (_ending || !keys.contains(key)) return;
    hide();
    selectedKey = key;
    _clearStatus();
    notifyListeners();
  }

  void clearUnlockError() {
    if (unlockError == null) return;
    unlockError = null;
    if (!_ending) notifyListeners();
  }

  /// Leaving the current screen rather than starting new work. Dismissal is
  /// allowed while an operation is pending; opening another mutation or
  /// protection screen is not, because its discarded read still has to settle
  /// before the next SDK call starts.
  bool _dismisses(TuiView next) =>
      next == TuiView.browse ||
      next == TuiView.unlock ||
      next == formReturnView;

  void navigate(TuiView next) {
    if (_ending || (busy && !_dismisses(next))) return;
    if (next != view &&
        (next == TuiView.create ||
            next == TuiView.passphrase ||
            next == TuiView.reset)) {
      formReturnView = view;
    }
    hide();
    view = next;
    unlockError = null;
    _clearStatus();
    notifyListeners();
  }

  Future<void> open([Uint8List? phrase]) {
    if (busy || _ending || hasSession) {
      clearBytes(phrase);
      return Future.value();
    }
    // Keep the same form through a credential check, including failed retries.
    if (view != TuiView.unlock) view = TuiView.opening;
    unlockError = null;
    resetFromFailure = false;
    return _perform(
      (token) async {
        TuiSession opened;
        try {
          authorize();
          final opening = openSession(phrase: phrase);
          clearBytes(phrase);
          opened = await opening;
        } finally {
          clearBytes(phrase);
        }
        if (!_current(token)) {
          await opened.close();
          return;
        }
        _session = opened;
        await _refresh();
        if (!_current(token)) return;
        view = opened.wasInitialized ? TuiView.firstUse : TuiView.browse;
        _clearStatus();
      },
      opening: true,
      ownedInput: phrase,
    );
  }

  Future<void> _refresh() async {
    final session = _session!;
    final names = (await session.listKeys()).toList()..sort();
    final passphrase = await session.passphraseId();
    if (_ending || !identical(session, _session)) return;
    keys = List.unmodifiable(names);
    _passphrase = passphrase;
    final matches = visibleKeys;
    if (!matches.contains(selectedKey)) selectedKey = matches.firstOrNull;
  }

  bool _current(int token) => !_ending && token == _intent;

  Future<void> read({bool edit = false, bool copy = false}) {
    if (busy ||
        _ending ||
        view != TuiView.browse ||
        selectedKey == null ||
        _session == null) {
      return Future.value();
    }
    if (copy && copyText == null) {
      message('Copy is unavailable on this desktop.', failure: true);
      return Future.value();
    }
    if (!copy && !edit && revealed) {
      hide();
      return Future.value();
    }
    final key = selectedKey!;
    if (edit && !isValidCliKey(key)) {
      message(
        'This name is outside the CLI key grammar and cannot be edited here.',
        failure: true,
      );
      return Future.value();
    }
    if (!copy) hide();
    return _perform(
      (token) async {
        Uint8List? bytes;
        final borrowed = copy && _value != null;
        try {
          bytes = borrowed ? _value : await _session!.getBytes(key);
          if (!_current(token)) return;
          if (bytes == null) {
            await _refresh();
            message('This key no longer exists.', failure: true);
            return;
          }
          final text = decodeTuiValue(bytes);
          authorize();
          if (copy) {
            await copyText!(text);
            if (_current(token)) {
              message('Copied!');
            }
          } else {
            _value = bytes;
            _valueText = null;
            _valueDisplayWidth = null;
            bytes = null;
            if (error && messageScope == _operationScope) _clearStatus();
            if (edit) {
              // Edit is entered from the vault without passing through
              // [navigate], so record its return target here as well.
              formReturnView = TuiView.browse;
              view = TuiView.edit;
            }
          }
        } finally {
          if (!borrowed) clearBytes(bytes);
        }
      },
      scope: (
        copy
            ? _RecordAction.copy
            : edit
            ? _RecordAction.edit
            : _RecordAction.reveal,
        key,
      ),
    );
  }

  /// Transfer the current edit value to an operation-owned field controller.
  /// Called on form mount, never during a build of an existing form.
  String takeEditText() {
    final text = valueText;
    _clearValue();
    return text;
  }

  String? recordNameError(String key, {required bool replace}) {
    if (key.isEmpty) return 'Enter a key name.';
    if (!isValidCliKey(key)) return 'Use a name like api-key or acme/key.';
    if (!replace && keys.contains(key)) {
      return 'That key exists. Choose another name.';
    }
    return null;
  }

  Future<void> save(String key, Uint8List bytes, {required bool replace}) {
    if (busy ||
        _ending ||
        _session == null ||
        (view != TuiView.create && view != TuiView.edit)) {
      clearBytes(bytes);
      return Future.value();
    }
    final nameError = recordNameError(key, replace: replace);
    if (nameError != null) {
      clearBytes(bytes);
      message(nameError, failure: true);
      return Future.value();
    }
    try {
      decodeTuiValue(bytes);
    } on FormatException {
      clearBytes(bytes);
      message('Enter valid UTF-8 without NUL, at most 1 MiB.', failure: true);
      return Future.value();
    }
    return _perform((token) async {
      try {
        final writing = _session!.setBytes(key, bytes);
        clearBytes(bytes);
        await writing;
      } finally {
        clearBytes(bytes);
      }
      await _refresh();
      if (!_current(token)) return;
      // Editing keeps the user's search context. A newly created key only
      // clears a filter when that filter would hide the result.
      if (!replace && !key.toLowerCase().contains(query.toLowerCase())) {
        query = '';
      }
      selectedKey = key;
      view = TuiView.browse;
      message('Saved!');
    }, ownedInput: bytes);
  }

  Future<void> deleteSelected() {
    if (view != TuiView.delete || selectedKey == null) return Future.value();
    final key = selectedKey!;
    return _perform((token) async {
      await _session!.delete(key);
      await _refresh();
      if (_current(token)) {
        view = TuiView.browse;
        message('Deleted!');
      }
    });
  }

  Future<void> clearRecords() {
    if (view != TuiView.clear) return Future.value();
    return _perform((token) async {
      await _session!.clearAll();
      await _refresh();
      if (_current(token)) {
        view = TuiView.browse;
        message('Records cleared; protection retained.');
      }
    });
  }

  Future<void> changePassphrase(Uint8List phrase) {
    if (busy || _ending || _session == null || view != TuiView.passphrase) {
      clearBytes(phrase);
      return Future.value();
    }
    if (phrase.isEmpty || phrase.length > 1024) {
      clearBytes(phrase);
      message('Passphrases must be 1–1024 UTF-8 bytes.', failure: true);
      return Future.value();
    }
    return _perform(
      (token) async {
        try {
          final changing = _session!.changePassphrase(
            phrase,
            replacing: protected,
          );
          clearBytes(phrase);
          await changing;
        } finally {
          clearBytes(phrase);
        }
        await _refresh();
        if (_current(token)) {
          view = TuiView.security;
          message('Passphrase protection updated.');
        }
      },
      protection: true,
      ownedInput: phrase,
    );
  }

  Future<void> removePassphrase() {
    if (view != TuiView.removePassphrase || _passphrase == null) {
      return Future.value();
    }
    return _perform((token) async {
      await _session!.removePassphrase(_passphrase!);
      await _refresh();
      if (_current(token)) {
        view = TuiView.security;
        message('Passphrase removed; platform protection remains.');
      }
    }, protection: true);
  }

  Future<void> reset(String confirmation) {
    if (view != TuiView.reset || confirmation != resetConfirmation) {
      message('Type $resetConfirmation to confirm.', failure: true);
      return Future.value();
    }
    return _perform((token) async {
      await _closeSession();
      await resetStore();
      if (!_ending) {
        status = 'Keybay reset. No replacement store was created.';
        // Complete this action before close waits on the pending operation.
        scheduleMicrotask(() => unawaited(close()));
      }
    }, resetting: true);
  }

  Future<void> _perform(
    Future<void> Function(int) operation, {
    bool opening = false,
    bool protection = false,
    bool resetting = false,
    Uint8List? ownedInput,
    Object? scope,
  }) {
    if (busy || _ending) {
      clearBytes(ownedInput);
      return Future.value();
    }
    final token = ++_intent;
    final completion = Completer<void>();
    _pending = completion.future;
    _operationScope = scope ?? view;
    // Starting a retry does not resolve the previous failure.
    _busyTimer = Timer(tuiBusyDelay, () {
      if (_ending || _pending == null) return;
      _showsBusy = true;
      notifyListeners();
    });
    notifyListeners();
    unawaited(() async {
      try {
        authorize();
        await operation(token);
      } on TuiStoreException catch (failure) {
        if (_ending) return;
        _clearValue();
        var text = failure.message;
        if (resetting) {
          await _closeSession();
          view = TuiView.failed;
          resetFromFailure = failure.resetIncomplete;
        } else if (opening) {
          await _closeSession();
          view = failure.unlock == null ? TuiView.failed : TuiView.unlock;
          if (view == TuiView.unlock) {
            unlockError = failure.unlock == TuiUnlockFailure.incorrect
                ? 'Could not unlock. Check your passphrase and try again.'
                : null;
            text = '';
          }
          resetFromFailure = failure.canReset;
        } else if (protection || failure.invalidatesSession) {
          await _closeSession();
          view = TuiView.failed;
          resetFromFailure = false;
          text =
              'The session is no longer usable. Reopen to authenticate the current state.';
        }
        if (text.isEmpty) {
          _clearStatus();
        } else {
          message(text, failure: true);
        }
      } on TuiCopyException {
        if (!_ending) {
          message(
            'Copy could not be confirmed. The clipboard may have changed.',
            failure: true,
          );
        }
      } on FormatException {
        if (!_ending) {
          message(
            'This value cannot be used as UTF-8 text without NUL (limit: 1 MiB).',
            failure: true,
          );
        }
      } on Object {
        await _closeSession();
        if (!_ending) {
          view = TuiView.failed;
          resetFromFailure = false;
          message(
            'The operation failed. Reopen to inspect current state.',
            failure: true,
          );
        }
      } finally {
        clearBytes(ownedInput);
        _busyTimer?.cancel();
        _busyTimer = null;
        _showsBusy = false;
        _pending = null;
        _operationScope = null;
        completion.complete();
        if (!_ending) notifyListeners();
      }
    }());
    return completion.future;
  }

  Future<void> _closeSession() async {
    final session = _session;
    _session = null;
    keys = const [];
    selectedKey = null;
    _passphrase = null;
    _clearValue();
    await session?.close();
  }

  Future<void> close({int code = 0}) => _closing ??= _close(code);

  Future<void> _close(int code) async {
    _ending = true;
    unlockError = null;
    _clearStatus();
    exitCode = code;
    _intent++;
    _clearValue();
    view = TuiView.closing;
    notifyListeners();
    try {
      await _pending;
      await _closeSession();
    } finally {
      onExit();
    }
  }

  @override
  void dispose() {
    _busyTimer?.cancel();
    super.dispose();
  }
}

void clearBytes(Uint8List? bytes) => bytes?.fillRange(0, bytes.length, 0);

String decodeTuiValue(Uint8List bytes) {
  if (bytes.length > tuiRecordValueBytes || bytes.contains(0)) {
    throw const FormatException();
  }
  return utf8.decode(bytes, allowMalformed: false);
}

/// Whether [text] contains anything [safeTuiText] would rewrite, i.e. whether a
/// live editor has to be replaced by a read-only escaped preview. A backslash
/// alone does not require that.
bool needsTuiEscaping(String text, {required bool allowNewlines}) {
  for (final cluster in text.characters) {
    for (final rune in cluster.runes) {
      if (rune == 0x0a) {
        if (!allowNewlines) return true;
      } else if (mustEscapeRune(rune)) {
        return true;
      }
    }
    if (_hidesKeptText(cluster)) return true;
  }
  return false;
}

const _widths = DefaultWidthResolver();

/// Cells one grapheme cluster occupies once escaped: exactly what the
/// renderer draws for [_escapeCluster]'s output.
int _clusterWidth(String cluster) {
  final escaped = _escapeCluster(cluster);
  return identical(escaped, cluster)
      ? _widths.widthOfGrapheme(cluster, CellWidthPolicy.spec)
      : _drawnWidth(escaped);
}

int _drawnWidth(String text) {
  var width = 0;
  for (final cluster in text.characters) {
    width += _widths.widthOfGrapheme(cluster, CellWidthPolicy.spec);
  }
  return width;
}

/// The runes of [cluster] that are shown as themselves would occupy no cells:
/// a stray combining mark or selector, for example. Show them escaped so no
/// stored code point silently disappears from the display.
bool _hidesKeptText(String cluster) {
  if (_isPlainAscii(cluster)) return false;
  final kept = StringBuffer();
  for (final rune in cluster.runes) {
    if (rune != 0x0a && !mustEscapeRune(rune)) kept.writeCharCode(rune);
  }
  return kept.isNotEmpty && _drawnWidth(kept.toString()) == 0;
}

/// A single printable ASCII character other than backslash: the common case,
/// which is always drawn as itself in one cell.
bool _isPlainAscii(String cluster) {
  if (cluster.length != 1) return false;
  final unit = cluster.codeUnitAt(0);
  return unit >= 0x20 && unit < 0x7f && unit != 0x5c;
}

/// Rewrites one grapheme cluster. Returns [cluster] itself when unchanged.
String _escapeCluster(String cluster) {
  if (_isPlainAscii(cluster)) return cluster;
  var changed = false;
  for (final rune in cluster.runes) {
    if (rune == 0x0a || rune == 0x5c || mustEscapeRune(rune)) {
      changed = true;
      break;
    }
  }
  final hideKept = _hidesKeptText(cluster);
  if (!changed && !hideKept) return cluster;
  final out = StringBuffer();
  for (final rune in cluster.runes) {
    if (rune == 0x0a) {
      out.writeln();
    } else if (rune == 0x5c) {
      out.write(r'\\');
    } else if (hideKept || mustEscapeRune(rune)) {
      out.write('\\u{${rune.toRadixString(16)}}');
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}

/// Cells the escaped form of one line occupies. The line must not contain LF.
int escapedLineWidth(String line) {
  var width = 0;
  for (final cluster in line.characters) {
    width += _clusterWidth(cluster);
  }
  return width;
}

/// Width of the widest escaped display line. Layout decisions ask this before
/// the value is escaped, so it never builds the escaped form to measure it.
int longestEscapedLine(String text) {
  var longest = 0;
  for (final line in text.split('\n')) {
    final width = escapedLineWidth(line);
    if (width > longest) longest = width;
  }
  return longest;
}

/// Splits one escaped line into rows of at most [width] cells, never breaking a
/// grapheme cluster. A cluster wider than the whole row still gets its own row.
List<String> wrapEscapedLine(String line, int width) {
  if (line.isEmpty) return const [''];
  final rows = <String>[];
  final row = StringBuffer();
  var used = 0;
  for (final cluster in line.characters) {
    final cells = _widths.widthOfGrapheme(cluster, CellWidthPolicy.spec);
    if (used > 0 && used + cells > width) {
      rows.add(row.toString());
      row.clear();
      used = 0;
    }
    row.write(cluster);
    used += cells;
  }
  if (row.isNotEmpty) rows.add(row.toString());
  return rows;
}

/// Rewrites only what [mustEscapeRune] identifies, plus any cluster text that
/// would be drawn in zero cells, preserving the exact source separately for
/// Copy/Edit. No stored byte can become a terminal command or vanish, and
/// ordinary international text stays readable.
String safeTuiText(String text) {
  final out = StringBuffer();
  for (final cluster in text.characters) {
    out.write(_escapeCluster(cluster));
  }
  return out.toString();
}
