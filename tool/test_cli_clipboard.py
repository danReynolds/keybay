#!/usr/bin/env python3
"""Typed clipboard round trip against an isolated board / X server."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import uuid

SAMPLE = '{\\rtf1 this is plain text}\r\n🔑 café\n'.encode()

def main():
    binary = os.path.abspath(sys.argv[1])
    if sys.platform == 'darwin':
        name = 'dev.keybay.test.' + uuid.uuid4().hex
        subprocess.run([binary, name], check=True)
        with tempfile.TemporaryDirectory(prefix='keybay-clipboard-') as work:
            script = Path(work) / 'check.swift'
            script.write_text('''import AppKit
let board = NSPasteboard(name: NSPasteboard.Name(CommandLine.arguments[1]))
defer { board.releaseGlobally() }
guard let value = board.string(forType: .string) else { exit(1) }
FileHandle.standardOutput.write(Data(value.utf8))
''')
            result = subprocess.run(['/usr/bin/swift', str(script), name], capture_output=True, check=True)
            assert result.stdout == SAMPLE, 'typed pasteboard did not preserve exact UTF-8'
        print('macOS typed clipboard: exact UTF-8/CRLF/RTF-prefix round trip passed on a private board.')
    elif sys.platform.startswith('linux'):
        # The caller owns a fresh Xvfb display. Never use the desktop clipboard.
        assert os.environ.get('KEYBAY_TEST_X11') == '1'
        subprocess.run([binary], check=True)
        result = subprocess.run(['/usr/bin/xclip', '-selection', 'clipboard', '-out', '-target', 'UTF8_STRING'], capture_output=True, check=True, timeout=5)
        assert result.stdout == SAMPLE, 'X11 clipboard did not preserve exact UTF-8'
        print('Linux X11 clipboard: exact UTF-8/CRLF/RTF-prefix round trip passed on isolated Xvfb.')

if __name__ == '__main__':
    main()
