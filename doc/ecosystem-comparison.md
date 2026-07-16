# Choosing Keybay

Keybay is a local secret store, not a universal secrets platform. Choose it
when each developer owns their local values and the application needs either a
small Dart API or run-scoped environment injection without an account, hosted
control plane, provider configuration, or resident Keybay process.

## The short decision

Choose Keybay when all of these are true:

- the supported target is iOS, Android 12+, macOS, or Linux desktop;
- values should stay on the current device and do not need team distribution;
- one fixed, documented storage policy per runtime is preferable to backend
  selection;
- Dart reads the store directly, or a macOS/Linux process already reads
  environment variables; and
- an unavailable platform store should fail closed rather than fall back.

Choose something else when you need Windows or headless deployment, hosted
sync, access administration, audit logs, provider portability, environment
profiles, automatic generation, or a secret that travels with an encrypted
project file.

## Category comparison

These tools overlap at process launch, but solve different ownership and
distribution problems.

| Tool | Best fit | Storage and distribution model | Added surface |
|---|---|---|---|
| **Keybay** | Per-developer local values; Dart/Flutter access; austere macOS/Linux launch injection | Per-app SDK stores; one per-user CLI store with qualified key names; fixed OS-backed runtime policy; no sync | One SDK constructor, or five CLI commands and one small manifest |
| [SecretSpec](https://secretspec.dev/) | One declaration across development, CI, and production | Pluggable keyrings, password managers, and cloud providers; profiles and fallback chains | Provider configuration, profiles, generation, migration, auditing, and language SDKs |
| [1Password CLI](https://www.1password.dev/cli/secrets-environment-variables) | Shared vaults, managed access, and team or service-account workflows | Values live in 1Password and are referenced by vault/item/field or an Environment | Account, authentication, vault policy, and the broader 1Password system |
| [dotenvx](https://dotenvx.com/) | Encrypted environment files that travel with a project or deployment | Encrypted values live in files and are decrypted with the corresponding key | File/key distribution and dotenv-compatible workflow |
| [flutter_secure_storage](https://pub.dev/packages/flutter_secure_storage) | Flutter-specific storage controls or platforms Keybay does not support | Platform-specific secure-storage implementations selected through a Flutter plugin | Flutter/plugin integration and a wider per-platform option surface |

This is not a security leaderboard. A local OS-backed store, a hosted team
vault, and an encrypted deployable file protect different boundaries. The
smallest appropriate tool is the one whose trust model matches where values
must live and who must receive them.

## What Keybay deliberately does not add

- **No provider abstraction.** There is no Vault, AWS, GCP, password-manager,
  or dotenv backend to select.
- **No profiles or precedence graph.** A manifest contains literals and explicit
  `kb://` references; Keybay reads exactly one file.
- **No team identity or policy.** Qualified CLI names organize identity.
  Identical full names deliberately share a value in the same user's store;
  namespaces are not permissions.
- **No hosted recovery or escrow.** Losing the platform-store key loses the
  local store.
- **No deployment story.** Headless and CI environments should use the
  deployment platform's own secret system.

Those omissions are the value proposition when the requirement is local
storage. They are disqualifiers when the requirement is distribution or
central administration.

## Injection boundary

`keybay run` resolves every reference before launch, overlays only the
manifest-named values on the existing process environment, and replaces itself
with the requested command. Missing references launch nothing. After launch,
the values are ordinary child environment variables and may be inherited by
descendants or inspected by processes with sufficient same-user access.

Direct SDK reads are preferable when a Dart application can avoid environment
injection entirely.
