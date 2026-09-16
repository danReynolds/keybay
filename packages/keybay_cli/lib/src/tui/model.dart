import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:characters/characters.dart';
import 'package:fleury/fleury_core.dart';
import 'package:keybay/keybay.dart';

import '../application.dart' show SessionOpener;
import '../failure.dart';
import '../key.dart';
import 'clipboard.dart' show TuiCopyException;

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

/// Presentation state and one invocation-owned SDK session. Widgets never own
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

  final SessionOpener openSession;
  final Future<void> Function() resetStore;
  final void Function() authorize;
  final Future<void> Function(String)? copyText;
  final void Function() onExit;

  /// The host's idle-exit policy, for display. Null means it is disabled.
  /// The native runner owns enforcement; the annotation preview has no timer.
  final Duration? idleTimeout;
  KeybaySession? _session;
  PassphraseMethod? _passphrase;
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
        KeybaySession opened;
        try {
          authorize();
          final opening = openSession(
            credential: phrase == null
                ? null
                : PassphraseCredential(phrase: phrase),
          );
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
    final methods = await session.auth.list();
    if (_ending || !identical(session, _session)) return;
    keys = List.unmodifiable(names);
    _passphrase = methods.whereType<PassphraseMethod>().firstOrNull;
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
          final credential = PassphraseCredential(phrase: phrase);
          final changing = protected
              ? _session!.auth.update(credential)
              : _session!.auth.add(credential);
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
      await _session!.auth.remove(_passphrase!.id);
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
      } on KeybayException catch (failure) {
        if (_ending) return;
        _clearValue();
        var text = failureForKeybay(failure).lines.join('\n');
        if (resetting) {
          await _closeSession();
          view = TuiView.failed;
          resetFromFailure = failure.code == KeybayErrorCode.resetIncomplete;
        } else if (opening) {
          await _closeSession();
          view = switch (failure.code) {
            KeybayErrorCode.authRequired ||
            KeybayErrorCode.unlockFailed => TuiView.unlock,
            _ => TuiView.failed,
          };
          if (view == TuiView.unlock) {
            unlockError = failure.code == KeybayErrorCode.unlockFailed
                ? 'Could not unlock. Check your passphrase and try again.'
                : null;
            text = '';
          }
          resetFromFailure = const {
            KeybayErrorCode.platformKeyInvalidated,
            KeybayErrorCode.storeAuthenticationFailed,
            KeybayErrorCode.storeStateConflict,
          }.contains(failure.code);
        } else if (protection ||
            const {
              KeybayErrorCode.staleSession,
              KeybayErrorCode.storeAuthenticationFailed,
              KeybayErrorCode.storeStateConflict,
              KeybayErrorCode.sessionClosed,
              KeybayErrorCode.storageOperationFailed,
              KeybayErrorCode.platformOperationFailed,
            }.contains(failure.code)) {
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
  if (bytes.length > KeybayLimits.recordValueBytes || bytes.contains(0)) {
    throw const FormatException();
  }
  return utf8.decode(bytes, allowMalformed: false);
}

/// Code points that must never reach the terminal as themselves: C0 and C1
/// controls, DEL, and the invisible or format characters that can make what is
/// displayed disagree with what is stored — bidi overrides and isolates, joiners
/// and zero-width marks, line/paragraph separators, annotation and tag
/// characters, and lone surrogates. LF is layout and survives.
///
/// Everything else printable — accents, CJK, emoji — renders as itself. The
/// display is width-measured rather than assumed to be one cell per code unit,
/// so a wide glyph cannot overflow the column it was laid out in.
bool mustEscapeRune(int rune) =>
    rune < 0x20 && rune != 0x0a ||
    rune >= 0x7f && rune <= 0x9f ||
    rune == 0xad ||
    rune == 0x61c ||
    rune == 0x180e ||
    rune >= 0x200b && rune <= 0x200f ||
    rune >= 0x2028 && rune <= 0x202e ||
    rune >= 0x2060 && rune <= 0x206f ||
    rune >= 0xd800 && rune <= 0xdfff ||
    rune == 0xfeff ||
    rune >= 0xfff9 && rune <= 0xfffb ||
    rune >= 0x1d173 && rune <= 0x1d17a ||
    rune >= 0xe0000 && rune <= 0xe007f;

/// A backslash is rewritten too, so an escape can never be confused with
/// literal text that happens to look like one.
bool _rewrites(int rune) => rune == 0x5c || mustEscapeRune(rune);

/// Whether [text] contains anything [safeTuiText] would rewrite, i.e. whether a
/// live editor has to be replaced by a read-only escaped preview. A backslash
/// alone does not require that.
bool needsTuiEscaping(String text, {required bool allowNewlines}) {
  for (final rune in text.runes) {
    if (rune == 0x0a) {
      if (!allowNewlines) return true;
    } else if (mustEscapeRune(rune)) {
      return true;
    }
  }
  return false;
}

const _widths = DefaultWidthResolver();

/// Cells one grapheme cluster occupies once escaped. Clusters with nothing to
/// rewrite are measured whole, so presentation selectors and combining marks
/// keep the width the renderer will give them.
int _clusterWidth(String cluster) {
  var rewritten = false;
  for (final rune in cluster.runes) {
    if (_rewrites(rune)) {
      rewritten = true;
      break;
    }
  }
  if (!rewritten) {
    return _widths.widthOfGrapheme(cluster, CellWidthPolicy.spec);
  }
  var width = 0;
  for (final rune in cluster.runes) {
    width += rune == 0x5c
        ? 2
        : mustEscapeRune(rune)
        ? 4 + rune.toRadixString(16).length
        : _widths.widthOfGrapheme(
            String.fromCharCode(rune),
            CellWidthPolicy.spec,
          );
  }
  return width;
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

/// Rewrites only what [mustEscapeRune] identifies, preserving the exact source
/// separately for Copy/Edit. No stored byte can become a terminal command, and
/// ordinary international text stays readable.
String safeTuiText(String text) {
  final out = StringBuffer();
  for (final rune in text.runes) {
    if (rune == 0x0a) {
      out.writeln();
    } else if (rune == 0x5c) {
      out.write(r'\\');
    } else if (mustEscapeRune(rune)) {
      out.write('\\u{${rune.toRadixString(16)}}');
    } else {
      out.writeCharCode(rune);
    }
  }
  return out.toString();
}
