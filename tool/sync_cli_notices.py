#!/usr/bin/env python3
"""Keep the CLI archive's native dependency notices beside its package license."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parent.parent
output = root / "packages/keybay_cli/THIRD_PARTY_NOTICES.txt"
parts = ["Native hardware dependency notices for the Keybay CLI."]
for name in ("keypass", "libfido2", "libcbor", "openssl", "nlohmann-json"):
    parts.extend([name, (root / "tool/licenses" / (name + ".txt")).read_text().rstrip()])
expected = "\n\n".join(parts) + "\n"
if sys.argv[1:] == ["--check"]:
    if not output.exists() or output.read_text() != expected:
        raise SystemExit("CLI notices are stale; run python3 tool/sync_cli_notices.py")
elif not sys.argv[1:]:
    output.write_text(expected)
else:
    raise SystemExit("usage: sync_cli_notices.py [--check]")
