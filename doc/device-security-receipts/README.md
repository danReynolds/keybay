# Device security receipts

This directory is reserved for reviewed, sanitized evidence from the
[native/device suite](../device-security-suite.md). Working logs stay in private
temporary storage under `build/device-security/` and are never committed.

Schema-v2 receipts bind a clean suite commit, canonical candidate-package
identity, exact installer input, verified harness package identity, target
facts, runner nonce, derived per-scenario outcomes, cleanup result, and retained
sanitized evidence. A release manifest accepts only passing receipts whose
subject and evidence hashes resolve exactly.

Before retaining any receipt, verify that it contains no canary/secret, raw
serial or UDID, account/team credential, device PIN, biometric data, private
key, token, or unreviewed raw log. Receipts are immutable historical records;
correct an erroneous result with a new run and review note, never by editing it.

Each candidate subject gets a digest-named subdirectory. Keep the unedited
receipt beside the exact structured-results file it names. Absence of a receipt
is an evidence gap, not a product pass or failure; Apple remains unqualified
until an eligible physical/signed-host run is deliberately performed.

After reviewing a private run directory, promote only its receipt and sanitized
result (never its raw log) with:

```sh
./tool/promote_device_receipt.sh build/device-security/RUN_DIRECTORY
```

The command refuses a non-pass, altered evidence, an unexpected file shape, or
an existing subject directory. The resulting files still require ordinary code
review before they become release-gate input.
