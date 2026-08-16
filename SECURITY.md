# Security policy

`keybay` stores credential material. Please treat vulnerabilities
accordingly.

## Reporting

Use GitHub's [private vulnerability reporting](https://github.com/danReynolds/keybay/security/advisories/new)
for suspected vulnerabilities. If GitHub is unsuitable, email
**me@danreynolds.ca**. Do not open a public issue for an undisclosed security
bug.

Include the affected version/configuration, impact, and the smallest safe
reproduction you can provide. Do not include real credentials or device
identifiers. Expect acknowledgement within three business days and an initial
scope/severity assessment within ten business days. Fix and disclosure timing
depends on impact and platform coordination; Keybay will coordinate publication
with the reporter rather than silently closing a valid report.

## Supported versions

While Keybay is pre-1.0, security fixes target the latest published minor line
and `main`. Older 0.x releases do not receive routine backports. A critical fix
may be backported when upgrading is not a practical mitigation; that decision
is stated in the advisory. Unsupported versions remain available but are not a
security-maintained configuration.

## Threat model

The threat model — what Keybay protects against and, just as importantly, what
it does **not** — is summarized for the [SDK](doc/sdk.md#threat-model) and
[CLI](packages/keybay_cli/README.md#security-boundary), then derived in full in
[doc/design.md](doc/design.md). Read it before relying on Keybay: it is
deliberate about its limits (process-memory disclosure, rollback, same-user
malware while the keystore is unlocked, and timing side-channels are out of
scope, with rationale).

## Device assurance

The [device security suite](doc/device-security-suite.md) turns platform and
lifecycle claims into versioned scenarios for Android, iOS, macOS, and later
Linux provider qualification. It distinguishes hermetic, native-host,
virtual-device, and physical-device evidence and defines how reviewed receipts
are retained.
The suite evolves as platform guidance and attack techniques change; historical
receipts remain scoped to their exact commit, target, OS, executable selection,
and scenarios.

## Cryptography

- Container confidentiality/integrity: XChaCha20-Poly1305 (AEAD), via
  `package:cryptography`, exercised against RFC 8439 and draft-arciszewski
  vectors in this package's own test suite so incompatible behavior is caught
  before the exact dependency pin moves. These checks do not prove a dependency
  uncompromised.
- Key derivation: HKDF-SHA256, RFC 5869, vector-tested here.
- Randomness: `Random.secure()` (OS CSPRNG) only.

## Dependencies

Exactly one third-party runtime dependency (`cryptography`, exact-pinned), whose
transitive closure is entirely dart-lang official. A dependency-closure snapshot
test fails CI if the tree changes; CI also runs advisory scanning.
