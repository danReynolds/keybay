# Security watchers

Keybay's watchers turn public security signals into a small, reviewable history. A finding means **review this**, not **Keybay is vulnerable**.

## Watcher definitions

| Watcher | Sources | Purpose |
| --- | --- | --- |
| Dependencies | OSV scans of every committed lockfile; new releases of specifically reviewed dependencies in `dependencies/reviewed.json` | Detects known resolved vulnerabilities and makes important upstream changes visible |
| Platforms | Apple security releases; Android security bulletins; narrow OSV coverage for the Linux Secret Service, KWallet, and D-Bus trust chain | Detects provider changes that package scanners cannot see |
| Peers | OSV plus recent GitHub issues, pull requests, and releases for the defined Flutter, native, React Native, Go, Rust, and Python peers | Reuses peer experience as red-team input without treating peers as dependencies |

Linux monitoring is deliberately narrow. Generic distro and kernel CVEs remain the operating system's patching responsibility unless evidence connects them to a Keybay guarantee. Peer activity is limited to titles and links from the last 14 days; issue bodies and comments are not ingested.

## Report flow

GitHub runs all three watchers every Monday and can run any group on demand. Discovery is read-only. A failed or malformed source is recorded as failed, never as quiet.

Each run pushes one generated `security-report/*` branch containing:

- `reports/<date>-<run>-<attempt>/raw.md`: immutable, validated discovery output.
- `reports/<date>-<run>-<attempt>/assessment.md`: the separate Codex applicability review.
- `reports/SUMMARY.md`: the derived run history, assessment summary, and links to resulting actions.

The scheduled Codex task follows [INSTRUCTIONS.md](INSTRUCTIONS.md), verifies the generated branch, opens one PR, completes its assessment, and updates the summary. Applicable public work becomes a normal GitHub issue. A plausible undisclosed Keybay vulnerability becomes a private draft security advisory; the public report contains only a generic label and the advisory's opaque private URL. Normal CI and review gate the final squash merge to `main`.

Physical-device testing is triggered only when a finding or code change can affect an OS, hardware, entitlement, lifecycle, or provider-dependent claim. It is not a weekly chore.

## Run it

In GitHub, open **Actions → Security watchers → Run workflow**, keep the branch on `main`, and choose `all` or one watcher. The workflow stages a pending assessment branch even when the result is quiet or a source failed, so the Codex task can preserve every run.

For a local read-only check:

```sh
dart run watchers/watch.dart dependencies --json
dart run watchers/watch.dart platforms --json
dart run watchers/watch.dart peers --json
```

`platforms --backfill` inspects the fixed bootstrap window without changing its forward boundary. Do not casually advance the platform boundary or peer baseline: those are reviewed history, not routine state.

GitHub may disable schedules after prolonged public-repository inactivity. The same workflow remains available through the Actions button; Dependabot and the required OSV pull-request check remain independent backstops.
