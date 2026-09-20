"""Small, fixed-repository adapters for the security watcher tools."""

import json
import subprocess

REPOSITORY = "danReynolds/keybay"


class CommandError(subprocess.CalledProcessError):
    def __str__(self):
        # GitHub's reason matters for unattended recovery. Request bodies and
        # stdout are deliberately excluded; credentials never enter argv.
        detail = (self.stderr or "").strip()[:2000]
        return super().__str__() + ("\n" + detail if detail else "")


def command(*args, input=None):
    try:
        return subprocess.run(
            args, input=input, text=True, capture_output=True, check=True, timeout=120
        ).stdout.strip()
    except subprocess.CalledProcessError as error:
        raise CommandError(error.returncode, error.cmd, error.stdout, error.stderr) from error


def api(path, body=None, method=None):
    args = ["gh", "api", path if path == "graphql" else f"repos/{REPOSITORY}/{path}"]
    if method:
        args.extend(["--method", method])
    if body is not None:
        args.extend(["--input", "-"])
    result = command(*args, input=None if body is None else json.dumps(body))
    return json.loads(result) if result else None


def pages(path):
    """Read every REST page, refusing an unexpectedly unbounded collection."""
    separator = "&" if "?" in path else "?"
    for page in range(1, 101):
        result = api(f"{path}{separator}per_page=100&page={page}")
        if not isinstance(result, list):
            raise ValueError("Expected a GitHub list response")
        yield from result
        if len(result) < 100:
            return
    raise ValueError("GitHub collection exceeded the safety limit")


def metadata(content, kind):
    first = content.splitlines()[0] if content else ""
    prefix = f"<!-- keybay-watcher-{kind}: "
    if not first.startswith(prefix) or not first.endswith(" -->"):
        raise ValueError(f"Missing watcher {kind} metadata")
    value = json.loads(first[len(prefix):-4])
    if not isinstance(value, dict) or value.get("schema") != 1:
        raise ValueError(f"Invalid watcher {kind} metadata")
    return value
