# Security watchers

Watchers turn new public security information into a small GitHub issue queue.
They do not claim that Keybay is vulnerable. Every finding starts an
applicability decision against Keybay's code, platform behavior, and numbered
`KB-INV-*` guarantees.

## What is watched

| Watcher | Definition | Why it exists |
|---|---|---|
| Dependencies | Every committed lockfile in `dependencies/lockfiles.txt`, scanned by OSV | Finds known vulnerabilities in code Keybay actually resolves |
| Platforms | Apple iOS/macOS releases, Android security bulletins, and Ubuntu/Debian advisories for the Linux credential-store trust chain | Finds OS-provider changes that package lockfiles cannot see |
| Peers | A fixed set of comparable secret-storage libraries across Pub, PyPI, npm, Go, and Rust | Reuses peer failures as red-team input without treating peers as dependencies |
| Critical dependencies | Exact reviewed pins listed in `critical/config.json` | Makes a new security-critical release visible where advisory coverage is too sparse to trust alone |

Linux monitoring is intentionally narrow: `gnome-keyring`, `libsecret`,
KWallet, and D-Bus. Generic distro and kernel CVEs remain the operating
system's patching responsibility unless evidence connects them to a Keybay
guarantee.

## Method

1. Query only named official or aggregate sources. A timeout, malformed
   response, or changed page shape fails the run; it never means "quiet."
2. Emit identifiers, package/product names, and official links only. Advisory
   prose is untrusted input and is not copied into an issue.
3. Create one issue per dependency, peer, or Linux advisory; one per Android
   bulletin; and one roll-up per Apple release date.
4. Put a stable marker in the issue body. Open and closed issues both suppress
   duplicates, so dispositions are durable without a mutable repository
   ledger.
5. Close with a concrete non-applicability reason, or link the fix, regression
   test, device qualification, or temporary claim reduction. Move any newly
   discovered Keybay-specific vulnerability to a private security advisory.

Physical-device work is triggered only when an advisory can materially affect
runtime provider behavior or a security claim. It is not scheduled by these
watchers.

The peer baseline and platform `started_at` boundary record what predates this
automation. Do not advance them during routine triage: changing either one can
silently suppress public information. Updating a critical reviewed version is
likewise part of the package-review change, not watcher maintenance.

## Running the watchers

GitHub runs all watchers weekly. To run them yourself:

1. Open the repository's **Actions** tab.
2. Select **Security watchers**.
3. Choose **Run workflow**, leave the branch as `main`, and select `all` or one
   watcher.
4. Open the run for its result. New public signals become deduplicated issues;
   a quiet run creates nothing.

Manual issue-writing runs are accepted only from `main`, so an unreviewed
branch cannot replace a watcher script and inherit its token. Dependency and
critical-pin checks also run on every pull request and push to `main`.

GitHub may disable scheduled workflows after prolonged inactivity in a public
repository. Dependabot remains the dependency backstop, and the same checks
run again before the next change. If continuous monitoring during long
dormancy becomes necessary, move only the weekly trigger to an external
scheduler; keep these definitions and issue rules unchanged.
