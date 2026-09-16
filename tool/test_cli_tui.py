#!/usr/bin/env python3
"""Native Fleury lifecycle over the disposable production-SDK command harness."""
from __future__ import annotations

import errno
import fcntl
import os
import re
import signal
import struct
import subprocess
import sys
import threading
import termios

from test_cli_commands import Invocation


def main():
    cli = os.path.abspath(sys.argv[1])
    real = len(sys.argv) > 2 and sys.argv[2] == '--real-provider'
    passed = 0
    def check(args, action, **kwargs):
        nonlocal passed
        p = Invocation(cli, [*(['--test-command'] if real else []), *args, 'open'], **kwargs)
        fcntl.ioctl(p.master, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
        try:
            action(p)
            passed += 1
        finally:
            p.close()

    def native_pointer(p):
        # Emulate protocol replies through a real PTY; the application still
        # uses its production native driver, parser, layout and pointer router.
        p.receive(b'\x1b[?u\x1b[c')
        os.write(p.master, b'\x1b[?31u\x1b[?1;2c')
        p.output.clear()
        p.receive(b'\x1b]22;?default,pointer,text,ew-resize,ns-resize\x1b\\\x1b[c')
        replies = []
        for query, reply in [
            (b'\x1b]22;?', b'\x1b]22;1,1,1,1,1\x1b\\'),
            (b'?2026$p', b'\x1b[?2026;2$y'),
            (b'\x1b_G', b'\x1b_Gi=31;OK\x1b\\'),
            (b'\x1b[6n', b'\x1b[1;2R'),
            (b'\x1b[c', b'\x1b[?1;2c'),
        ]:
            replies.extend((match.start(), reply)
                           for match in re.finditer(re.escape(query), p.output))
        os.write(p.master, b''.join(reply for _, reply in sorted(replies)))
        p.receive(b'acme/key')
        assert b'\x1b]22;>default\x1b\\' in p.output
        # Search field, New key action, then ordinary header text (80x24).
        os.write(p.master, b'\x1b[<35;6;4M')
        p.receive(b'\x1b]22;text\x1b\\')
        os.write(p.master, b'\x1b[<35;4;20M')
        p.receive(b'\x1b]22;pointer\x1b\\')
        os.write(p.master, b'\x1b[<35;4;2M')
        p.receive(b'\x1b]22;default\x1b\\')
        os.write(p.master, b'q')
        p.finish(0)
        assert p.output.count(b'\x1b]22;>default\x1b\\') == 1
        assert p.output.count(b'\x1b]22;<\x1b\\') == 1
        assert p.output.index(b'\x1b]22;<\x1b\\') < p.output.index(b'\x1b[?1049l')
        assert b'disposable-value' not in p.output
    # Protocol emulation uses the synthetic harness's platform-only fixture.
    # The real-provider lane below opens its already-protected disposable store.
    if not real:
        check(['--platform-only'], native_pointer)

    def browse(p):
        p.receive(b'acme/key')
        assert b'disposable-value' not in p.output
        os.write(p.master, b' ')
        p.receive(b'disposable-value')
        os.write(p.master, b'q')
        p.finish(0)
        assert b'\x1b[?1049l' in p.output, 'alternate screen not restored'
    if not real:
        check(['--platform-only'], browse)

    def unlock(p):
        p.receive(b'Unlock Keybay')
        assert b'acme/key' not in p.output
        assert not termios.tcgetattr(p.master)[3] & termios.ECHO
        os.write(p.master, b'disposable-passphrase\r')
        p.receive(b'acme/key')
        assert b'disposable-passphrase' not in p.output
        assert b'disposable-value' not in p.output
        os.write(p.master, b' ')
        p.receive(b'disposable-value')
        os.write(p.master, b'q')
        p.finish(0)
    check([], unlock)
    if real:
        print('TUI real-provider regression: protected open, masked phrase, explicit reveal, session close and terminal restoration passed.')
        return

    def unlock_retry(p):
        p.receive(b'Unlock Keybay')
        assert b'Opening Keybay' not in p.output, 'fast startup flashed opening'
        p.output.clear()
        os.write(p.master, b'wrong-passphrase\r')
        p.receive(b'Unlocking')
        p.receive(b'Could not unlock.')
        assert b'Opening Keybay' not in p.output, 'retry replaced the unlock form'
        assert b'wrong-passphrase' not in p.output
        assert b'acme/key' not in p.output
        p.output.clear()
        # No Tab/click is needed to type again after a failed check.
        os.write(p.master, b'disposable-passphrase\r')
        p.receive(b'Unlocking')
        p.receive(b'acme/key')
        assert b'Opening Keybay' not in p.output
        assert b'disposable-passphrase' not in p.output
        assert b'disposable-value' not in p.output
        os.write(p.master, b'q')
        p.finish(0)
    check(['--delay-unlock'], unlock_retry)

    def settings(p):
        p.receive(b'acme/key')
        os.write(p.master, b's')
        p.receive(b'Add passphrase')
        os.write(p.master, b'\x1b[B\r')
        p.receive(b'Delete every saved key and value.')
        os.write(p.master, b'\r')
        p.receive(b'Clear all records?')
        p.output.clear()
        os.write(p.master, b'\x1b')
        p.receive(b'Delete every saved key and value.')
        os.write(p.master, b'r')
        p.receive(b'Type RESET to confirm:')
        p.output.clear()
        os.write(p.master, b'\x1b')
        p.receive(b'Delete every saved key and value.')
        # Return to the sidebar and choose Security without leaving Settings.
        os.write(p.master, b'\x1b[D\x1b[A')
        p.receive(b'Add passphrase')
        os.write(p.master, b'p')
        p.receive(b'Confirm passphrase')
        p.output.clear()
        os.write(p.master, b'\x1b')
        p.receive(b'Require a passphrase')
        p.output.clear()
        os.write(p.master, b'\x1b')
        p.receive(b'acme/key')
        os.write(p.master, b'q')
        p.finish(0)
        assert b'disposable-value' not in p.output
    check(['--platform-only'], settings)

    def passphrase_mismatch(p):
        p.receive(b'acme/key')
        os.write(p.master, b's')
        p.receive(b'Security')
        os.write(p.master, b's')
        p.receive(b'Add passphrase')
        os.write(p.master, b'p')
        p.receive(b'Confirm passphrase')
        os.write(p.master, b'disposable-draft\rdisposable-drafX\x13')
        p.receive(b"Passphrases don't match.")
        # Correction works in place: both fields survived, focus is on confirm.
        os.write(p.master, b'\x7ft\x13')
        p.receive(b'Passphrase protection updated.')
        assert b'disposable-draft' not in p.output
        assert b'disposable-drafX' not in p.output
        p.output.clear()
        os.write(p.master, b'\x1b')
        p.receive(b'acme/key')
        os.write(p.master, b'q')
        p.finish(0)
    check(['--platform-only'], passphrase_mismatch)

    def search_space(p):
        p.receive(b'acme/key')
        os.write(p.master, b'/acme ')
        p.receive(b'No matching keys')
        assert b'disposable-value' not in p.output
        p.output.clear()
        os.write(p.master, b'\x7f\r')
        p.receive(b'acme/key')
        os.write(p.master, b'\r')
        p.receive(b'[Ctrl+S]')
        assert b'disposable-value' not in p.output
        p.output.clear()
        os.write(p.master, b'\x1b')
        p.receive(b'acme/key')
        os.write(p.master, b'q')
        p.finish(0)
    check(['--platform-only'], search_space)

    def enter_edits(p):
        p.receive(b'acme/key')
        assert b'\x1b[?1003h' in p.output, 'hover tracking not enabled'
        os.write(p.master, b'\r')
        p.receive(b'[Ctrl+S]')
        assert b'disposable-value' not in p.output
        p.output.clear()
        os.write(p.master, b'\x1b')
        p.receive(b'acme/key')
        os.write(p.master, b' ')
        p.receive(b'disposable-value')
        p.output.clear()
        os.write(p.master, b' ')
        p.receive(b'Reveal')
        assert b'disposable-value' not in p.output
        os.write(p.master, b'q')
        p.finish(0)
    check(['--platform-only'], enter_edits)

    def create(p):
        p.receive(b'acme/key')
        os.write(p.master, b'n')
        p.receive(b'New key')
        os.write(p.master, b'tui-created\rdisposable-form-value\r')
        p.receive(b'Saved!')
        assert b'disposable-form-value' not in p.output
        os.write(p.master, b' ')
        p.receive(b'disposable-form-value')
        os.write(p.master, b'q')
        p.finish(0)
    check(['--platform-only'], create)

    def tab_form(p):
        p.receive(b'acme/key')
        os.write(p.master, b'n')
        p.receive(b'New key')
        # Name -> Value -> Name -> Value -> Save, through real terminal chords.
        os.write(p.master, b'tab-created\tdisposable-tab-value\x1b[Z\r\t\r')
        p.receive(b'Saved!')
        assert b'disposable-tab-value' not in p.output
        os.write(p.master, b' ')
        p.receive(b'disposable-tab-value')
        os.write(p.master, b'q')
        p.finish(0)
    check(['--platform-only'], tab_form)

    def form_shortcuts(p):
        p.receive(b'acme/key')
        os.write(p.master, b'e')
        p.receive(b'[Ctrl+S]')
        assert not termios.tcgetattr(p.master)[0] & termios.IXON, 'Ctrl+S would pause output'
        assert b'disposable-value' not in p.output
        os.write(p.master, b'\x12')  # Ctrl+R reveals with the field focused.
        # The caret renders the first character with a separate inverse style.
        p.receive(b'isposable-value')
        p.output.clear()
        os.write(p.master, b'\x12')
        p.receive(b'Reveal')
        p.output.clear()
        os.write(p.master, b'\x13')  # Ctrl+S saves without moving to the button.
        p.receive(b'Saved!')
        assert b'disposable-value' not in p.output
        os.write(p.master, b' ')
        p.receive(b'disposable-value')
        os.write(p.master, b'q')
        p.finish(0)
    check(['--platform-only'], form_shortcuts)

    def correct_name(p):
        p.receive(b'acme/key')
        os.write(p.master, b'n')
        p.receive(b'New key')
        os.write(p.master, b'bad key\tretained-draft-value\x13')
        p.receive(b'Use a name like')
        assert b'retained-draft-value' not in p.output
        # Validation returns focus to Key; the caret is at its original end.
        os.write(p.master, b'\x7f' * 7 + b'corrected\x13')
        p.receive(b'Saved!')
        os.write(p.master, b' ')
        p.receive(b'retained-draft-value')
        os.write(p.master, b'q')
        p.finish(0)
    check(['--platform-only'], correct_name)

    def empty_search(p):
        p.receive(b'acme/key')
        os.write(p.master, b'/unmatched')
        p.receive(b'No matching keys')
        p.output.clear()
        os.write(p.master, b'\x1b')
        p.receive(b'acme/key')
        os.write(p.master, b'q')
        p.finish(0)
    check(['--platform-only'], empty_search)

    def edit_blur(p):
        p.receive(b'acme/key')
        os.write(p.master, b'e')
        p.receive(b'[Ctrl+S]')
        os.write(p.master, b'\x12')
        p.receive(b'isposable-value')
        p.output.clear()
        os.write(p.master, b'\x1b[O')
        p.receive(b'Reveal')
        assert b'isposable-value' not in p.output
        os.write(p.master, b'\x1b[I\x13')
        p.receive(b'Saved!')
        os.write(p.master, b' ')
        p.receive(b'disposable-value')
        os.write(p.master, b'q')
        p.finish(0)
    check(['--platform-only'], edit_blur)

    def draft_resize(p):
        p.receive(b'acme/key')
        os.write(p.master, b'n')
        p.receive(b'New key')
        p.output.clear()  # Do not match the earlier vault's mask.
        os.write(p.master, b'draft-kept\tpreserved-secret')
        p.receive(b'\x1b[13;29H')  # Caret after the entire 16-character value.
        fcntl.ioctl(p.master, termios.TIOCSWINSZ, struct.pack('HHHH', 12, 30, 0, 0))
        p.receive(b'Draft kept hidden.')
        p.output.clear()
        fcntl.ioctl(p.master, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
        p.receive(b'New key')
        assert b'preserved-secret' not in p.output
        os.write(p.master, b'\x13')
        p.receive(b'Saved!')
        os.write(p.master, b' ')
        p.receive(b'preserved-secret')
        os.write(p.master, b'q')
        p.finish(0)
    check(['--platform-only'], draft_resize)

    def unlock_resize(p):
        p.receive(b'Unlock Keybay')
        os.write(p.master, b'disposable-')
        p.receive(b'\x1b[8;24H')  # Caret after the entire 11-character prefix.
        os.write(p.master, b'\x1b[O')
        fcntl.ioctl(p.master, termios.TIOCSWINSZ, struct.pack('HHHH', 12, 30, 0, 0))
        p.receive(b'Draft kept hidden.')
        p.output.clear()
        fcntl.ioctl(p.master, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
        p.receive(b'Unlock Keybay')
        os.write(p.master, b'\x1b[Ipassphrase\r')
        p.receive(b'acme/key')
        assert b'disposable-passphrase' not in p.output
        os.write(p.master, b'q')
        p.finish(0)
    check([], unlock_resize)

    def delete_confirmation(p):
        p.receive(b'acme/key')
        os.write(p.master, b'd')
        p.receive(b'Delete this key?')
        p.output.clear()
        os.write(p.master, b'\r')  # Cancel owns initial focus.
        p.receive(b'acme/key')
        os.write(p.master, b'd')
        p.receive(b'Delete this key?')
        os.write(p.master, b'\t\r')
        p.receive(b'Deleted!')
        assert b'disposable-value' not in p.output
        os.write(p.master, b'q')
        p.finish(0)
    check(['--platform-only'], delete_confirmation)

    for pointer in (False, True):
        def search_focus(p, pointer=pointer):
            p.receive(b'acme/key')
            p.output.clear()
            # Search is row 4, the first result row 6 in the compact 80x24 layout.
            os.write(p.master, b'\x1b[<0;5;4M\x1b[<0;5;4m' if pointer else b'\x1b[A')
            # Search is case-insensitive. Await its unique final character;
            # terminal delta frames may paint each character separately.
            os.write(p.master, b'KEY')
            p.receive(b'Y')
            assert b'disposable-value' not in p.output
            os.write(p.master, b'\x1b[<0;5;6M\x1b[<0;5;6m' if pointer else b'\x1b[B')
            os.write(p.master, b' ')
            p.receive(b'disposable-value')
            os.write(p.master, b'q')
            p.finish(0)
        check(['--platform-only'], search_focus)

    def filtered_edit(p):
        p.receive(b'acme/key')
        os.write(p.master, b'/KEY\r ')
        p.receive(b'disposable-value')
        p.output.clear()
        os.write(p.master, b'\x1b')
        p.receive(b'Reveal')
        p.output.clear()
        os.write(p.master, b'e')
        p.receive(b'Alt+Enter new line')
        os.write(p.master, b'\x13')
        p.receive(b'Saved!')
        # A new vault view must restore the exact query after hide/edit/save.
        # It cannot come from the edit title, whose key is lowercase.
        p.receive(b'KEY')
        os.write(p.master, b'q')
        p.finish(0)
    check(['--platform-only'], filtered_edit)

    def stop(p, chord, status):
        p.receive(b'acme/key')
        os.write(p.master, chord)
        p.finish(status)
    check(['--platform-only'], lambda p: stop(p, b'\x1a', 0))
    check(['--platform-only'], lambda p: stop(p, b'\x03', 130))

    for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
        def terminate(p, sig=sig):
            p.receive(b'acme/key')
            os.kill(p.pid, sig)
            p.finish(128 + sig)
        check(['--platform-only'], terminate)

    def pending(p):
        p.receive(b'test:opening')
        os.kill(p.pid, signal.SIGTERM)
        p.finish(143)
        assert b'acme/key' not in p.output
        assert b'disposable-value' not in p.output
    check(['--platform-only', '--delay-open'], pending)

    def idle(p):
        p.receive(b'acme/key')
        p.receive('Closing soon without input.'.encode())
        p.finish(0)
        assert b'disposable-value' not in p.output
    check(['--platform-only', '--short-idle'], idle)

    def hover_does_not_extend_idle(p):
        p.receive(b'acme/key')
        stop_hover = threading.Event()
        hover_errors = []
        def hover():
            while not stop_hover.wait(.03):
                try:
                    os.write(p.master, b'\x1b[<35;4;17M')
                except OSError as error:
                    # The slave closes on idle exit, potentially before the
                    # reader observes test:closed. The main thread still
                    # verifies that marker and a successful process exit.
                    if error.errno != errno.EIO:
                        hover_errors.append(error)
                    return
        worker = threading.Thread(target=hover, daemon=True)
        worker.start()
        try:
            p.receive(b'test:closed', timeout=3)
            p.finish(0)
        finally:
            stop_hover.set()
            worker.join()
        assert not hover_errors, hover_errors
    check(['--platform-only', '--short-idle'], hover_does_not_extend_idle)

    def resize(p):
        p.receive(b'acme/key')
        os.write(p.master, b' ')
        p.receive(b'disposable-value')
        before = len(p.output)
        fcntl.ioctl(p.master, termios.TIOCSWINSZ, struct.pack('HHHH', 12, 30, 0, 0))
        p.receive(b'Resize to at least')
        assert b'disposable-value' not in p.output[before:]
        os.write(p.master, b'\x03')
        p.finish(130)
    check(['--platform-only'], resize)

    def focus_loss(p):
        p.receive(b'acme/key')
        os.write(p.master, b' ')
        p.receive(b'disposable-value')
        p.output.clear()
        os.write(p.master, b'\x1b[O')
        p.receive(b'Reveal')
        assert b'disposable-value' not in p.output
        os.write(p.master, b'q')
        p.finish(0)
    check(['--platform-only'], focus_loss)

    def refused(p):
        p.receive(b'foreground controlling terminal')
        p.finish(4)
        assert b'acme/key' not in p.output
        assert b'disposable-value' not in p.output + p.capture
        assert b'\x1b[?1049h' not in p.output + p.capture
    check(['--platform-only'], refused, capture=True)
    check(['--platform-only'], refused, pipe_input=b'input')
    check(['--platform-only'], refused, second_tty=True)

    for variable in ('FLEURY_ANSI_CAPTURE', 'FLEURY_RUNTIME_MARKERS', 'FLEURY_HANDLE'):
        previous = os.environ.get(variable)
        os.environ[variable] = '/not-used/keybay-capture'
        try:
            def unsafe_environment(p):
                p.receive(b'disable Fleury')
                p.finish(4)
                assert b'\x1b[?1049h' not in p.output
            check(['--platform-only'], unsafe_environment)
        finally:
            if previous is None:
                del os.environ[variable]
            else:
                os.environ[variable] = previous
    print(f'TUI PTY regression: {passed} passed (disposable SDK engine, native Fleury terminal).')


if __name__ == '__main__':
    main()
