# Device security receipts

This directory is reserved for reviewed, sanitized evidence from the
[native/device suite](../device-security-suite.md). Working logs stay in private
temporary storage under `build/device-security/` and are never committed.

The current schema-v1 receipt records a checkout, target facts, executable
selection, scenario statuses, and evidence hashes. It does not bind an exact
release subject or nonce-derived per-scenario output, so it is development
evidence and must not be promoted as a release-qualification receipt.

Release-eligible receipts will be retained with their sanitized evidence and
subject-specific release manifest after the exact-subject contract in the suite
is implemented. Every digest used by a gate must resolve to retained bytes.

Before retaining any receipt, verify that it contains no canary/secret, raw
serial or UDID, account/team credential, device PIN, biometric data, private
key, token, or unreviewed raw log. Receipts are immutable historical records;
correct an erroneous result with a new run and review note, never by editing it.

This directory intentionally contains no physical-device receipt yet. Absence
of a receipt is an evidence gap, not a product pass or failure.
