import 'dart:convert';
import 'dart:typed_data';

import 'package:fleury/fleury_core.dart';

import 'chrome.dart';
import 'model.dart';
import 'store.dart';

/// One operation-owned masked draft: its controller, focus node and byte
/// contract. Erasing empties and disposes the controller, then creates a fresh
/// one for any retry. This releases its text and undo history; `clear()` alone
/// would leave an undoable edit.
final class SecretDraft {
  SecretDraft({
    required this.limit,
    required this.allowNewlines,
    required this.allowNul,
  });

  /// A record value editor: multiline, and NUL is outside the value contract.
  SecretDraft.record()
    : this(limit: tuiRecordValueBytes, allowNewlines: true, allowNul: false);

  /// A passphrase field: single line, and any byte the user can type is
  /// accepted so an existing passphrase stays enterable.
  SecretDraft.passphrase()
    : this(limit: 1024, allowNewlines: false, allowNul: true);

  final int limit;
  final bool allowNewlines;
  final bool allowNul;
  final FocusNode focus = FocusNode();
  TextEditingController controller = TextEditingController(preserveText: true);
  bool _disposed = false;

  String get text => controller.text;

  /// Text the terminal cannot render literally goes through an escaped,
  /// read-only preview instead of a live editor.
  bool get needsEscaping =>
      needsTuiEscaping(text, allowNewlines: allowNewlines);

  /// Whether [text] still satisfies this draft's byte contract.
  bool accepts(String text) {
    final encoded = text.length > limit ? null : utf8.encode(text);
    final rejected =
        encoded == null ||
        encoded.length > limit ||
        (!allowNul && encoded.contains(0));
    if (encoded != null) encoded.fillRange(0, encoded.length, 0);
    return !rejected;
  }

  /// Snapshot the draft as caller-owned bytes for one SDK operation.
  Uint8List takeBytes() => Uint8List.fromList(utf8.encode(text));

  void erase() {
    if (_disposed) return;
    _empty();
    controller = TextEditingController(preserveText: true);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _empty();
    focus.dispose();
  }

  void _empty() {
    controller.value = TextEditingValue.empty();
    controller.dispose();
  }
}

/// Bordered field chrome. The focus detector rebuilds the form so the border
/// follows focus; the stable key keeps input routing attached as inline
/// feedback appears and disappears around the field.
mixin FormFields<T extends StatefulWidget> on State<T> {
  Widget field(
    Widget child, {
    required FocusNode focus,
    bool invalid = false,
  }) => FocusDetector(
    key: ValueKey(focus),
    onFocusChange: (_) => setState(() {}),
    child: Container(
      border: BoxBorder(
        cellStyle: invalid
            ? context.theme.errorStyle
            : focus.hasFocus
            ? context.theme.focusedStyle
            : context.theme.mutedStyle,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: child,
    ),
  );
}

/// Shared masked-draft lifecycle for the forms that can reveal their input.
/// Erase, conceal and preview swapping live here so a new form cannot quietly
/// skip the discipline.
mixin SecretDrafts<T extends StatefulWidget> on State<T>, FormFields<T> {
  TuiModel get model;
  List<SecretDraft> get drafts;

  int? _shownAtRevision;

  /// A conceal — blur, resize or a validation failure — bumps the model's
  /// revision, which expires any earlier reveal without its own cleanup path.
  bool get revealed => _shownAtRevision == model.concealRevision;
  set revealed(bool value) =>
      _shownAtRevision = value ? model.concealRevision : null;

  bool previewsEscaped(SecretDraft draft) => revealed && draft.needsEscaping;

  /// Clear inline validation feedback alongside the drafts it describes.
  void clearFieldErrors() {}

  void eraseDrafts() {
    revealed = false;
    clearFieldErrors();
    for (final draft in drafts) {
      draft.erase();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    revealed = false;
    for (final draft in drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  void toggleReveal() {
    if (model.busy) return;
    final focused = drafts.where((draft) => draft.focus.hasFocus).firstOrNull;
    // An escaped preview replaces the editor; keep focus on the same field.
    final swapsFocusedField = focused != null && focused.needsEscaping;
    setState(() => revealed = !revealed);
    if (swapsFocusedField) {
      final shown = revealed;
      TuiBinding.of(context).addPostFrameCallback((_) {
        if (mounted && revealed == shown) focused.focus.requestFocus();
      });
    }
  }

  /// Out-of-contract input dismisses the whole editor, including a scheduled
  /// paste tail and undo state. Erase before navigating so the drafts are
  /// released whether or not the unmount is deferred to a later frame.
  void checkSecret(SecretDraft draft, String text) {
    if (!draft.accepts(text)) {
      eraseDrafts();
      model.navigate(model.hasSession ? TuiView.browse : TuiView.unlock);
      model.message(
        'The draft was discarded: limit ${draft.limit} UTF-8 bytes${draft.allowNul ? '.' : '; no NUL.'}',
        failure: true,
      );
      return;
    }
    // Conceal newly entered controls without unmounting a pending paste.
    if (revealed && draft.needsEscaping) setState(() => revealed = false);
  }

  Widget secretField(
    Widget child, {
    required SecretDraft draft,
    bool invalid = false,
    int rows = 1,
  }) => field(
    DefaultTextStyle(
      style: revealed ? context.accents.attention : CellStyle.none,
      child: previewsEscaped(draft)
          ? SizedBox(
              height: rows,
              child: ValueView(text: draft.text, focusNode: draft.focus),
            )
          : child,
    ),
    focus: draft.focus,
    invalid: invalid,
  );

  /// Label suffix that states disclosure in words, so colour stays
  /// supplementary.
  String discloses(SecretDraft draft) => previewsEscaped(draft)
      ? ' · escaped preview'
      : revealed
      ? ' · revealed'
      : '';
}
