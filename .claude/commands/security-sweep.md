# /security-sweep — platform drift and peer review

Research-only session: report findings, change nothing. This sweep exists
because the most dangerous change for a secret-storage library is one that
breaks no test — the platform moving its recommendation while our code stays
green. Correctness is guarded by tests; *currency* is guarded by this sweep.

## Procedure

1. Establish the review window. Find the most recent closed issue titled
   "Security sweep" (or the sweep issue that dispatched this run) and use its
   close date as the window start; if none exists, use the last 60 days.

2. Read, for changes inside the window:
   - Apple security release notes and the Keychain Services / Data Protection
     documentation (accessibility constants, access groups,
     `kSecUseDataProtectionKeychain` behavior).
   - Android Keystore and backup/transfer guidance, plus behavior notes for
     any API level newly released or newly scheduled
     (Keystore, StrongBox, `KeyInfo`, `dataExtractionRules`).
   - Dart SDK changelog and any Dart/pub security advisories.
   - libsecret / GNOME Keyring release notes and the Secret Service
     specification.
   - Peer issue trackers and advisories beyond what OSV indexes:
     flutter_secure_storage, keyring (Python), keyring-rs, go-keyring,
     keytar successors, Electron safeStorage. Security-shaped open issues
     count even without a CVE.

3. Diff every finding against Keybay's model:
   - the platform matrix and mechanisms in `SECURITY.md`;
   - the `KB-INV-*` invariants and threat model in `doc/design.md`;
   - the per-platform contracts in `doc/platforms/*.md` (including each cited
     platform link — flag a citation whose target moved or changed meaning).

4. Report, in this exact shape:
   - **Applicable findings** — for each: the source (URL + date), what
     changed, which invariant or matrix row it touches, and a proposed
     disposition (new test, doc change, code change, or accepted with
     rationale). If none: state "No applicable findings."
   - **Watch items** — changes that do not apply yet but plausibly will
     (e.g., announced deprecations), each with the condition that would make
     them applicable.
   - **Sources examined** — the complete list of sources actually read, with
     the date range covered for each. Silence about a source is not coverage
     of it; a source that could not be checked is listed as NOT EXAMINED.

5. Do not edit code or docs, and do not open PRs. Findings are discussed in
   session; the maintainer records applicability decisions in the sweep issue
   and closes it. Only decisions recorded there count as triage.
