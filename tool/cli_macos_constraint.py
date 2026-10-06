#!/usr/bin/env python3
"""Pin the dedicated runtime to the exact signed module and hardware libraries."""
import pathlib
import plistlib
import re
import subprocess
import sys


def display(path):
    return subprocess.check_output(['codesign', '-dvvvvvv', str(path)], stderr=subprocess.STDOUT, text=True)


def hashes(bundle):
    result = set()
    for path in [bundle / 'keybay.aot', *bundle.glob('*.dylib')]:
        values = re.findall(r'^CandidateCDHash \w+=([a-f0-9]{40})$', display(path), re.M)
        if not values:
            raise ValueError(f'missing signed code hash: {path.name}')
        result.update(values)
    return result


def main():
    mode, directory = sys.argv[1:3]
    bundle = pathlib.Path(directory)
    expected = hashes(bundle)
    if mode == 'write':
        pathlib.Path(sys.argv[3]).write_bytes(plistlib.dumps({'cdhash': {'$in': [bytes.fromhex(h) for h in sorted(expected)]}}))
    elif mode == 'verify':
        text = display(bundle / 'keybay-runtime')
        keys = set(re.findall(r'^\s*\[Key\] (.*?)\s*$', text, re.M))
        actual = set(re.findall(r'^\s*\[Data\] (.*?)\s*$', text, re.M))
        if ('Has Library Load Constraints' not in text or actual != expected or
                keys - {'ccat', 'comp', 'reqs', 'vers', 'cdhash', '$in'}):
            raise ValueError('runtime library constraint differs from the signed companions')
    else:
        raise ValueError('expected write or verify')


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        raise SystemExit(f'invalid runtime constraint: {error}') from error
