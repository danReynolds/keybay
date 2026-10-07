# SDK release preparation, October 7, 2026

Passkey integration is already merged in PR #88. PR #91 prepares the hosted
release closure and monitoring. This is preparation evidence, not a publication
or new physical-device qualification claim.

## Changes reviewed

- Android's bulletin category page moved dated links to `asb-overview`; recent
  bulletin paths also gained a year directory. Accept only the two official
  date-path shapes, validate the date/year, preserve the referenced path, dedupe
  markers and reject empty/malformed input. Live discovery now includes the
  September and October 2026 bulletins.
- Keypass `0.1.0-dev.2` is hosted and monitored for new upstream releases.
- Fleury `0.1.1` includes the widget catalog. Replace Git sources with its hosted
  archive and `fleury_web` `0.1.1`, remove the override and migrate the notifier
  and exit names. The runtime closure loses the separate widgets package and
  adds no package. Keybay still injects its foreground-checking driver, disables
  hot reload/debug/clipboard/stray output, and rejects developer environment
  settings. `exitApp` retains the invocation lifetime semantics needed by cleanup.
- A manual all-source scan can restore monitoring freshness only after a
  completed assessment on main and an exact successful Actions run check.
  Missing/disabled schedules, partial scans and overdue assessments remain loud.
- SDK archive text describes the V1/V2 incompatibility and Keypass prerelease;
  platform guidance requires a maintained OS with current security updates.

Hosted Fleury archive SHA-256:
`afc9d8bd5e7753e34d2daffbd09d8c10a6e51f2194d408674dbfa58432ab661e`.
Hosted Fleury Web archive SHA-256:
`c69968942f13db5d111e99d05c6876cbd373da044b702d65a4182b2e7b064580`.

## Local validation

- Workspace analyzer clean; dependency closure checks and browser model tests pass.
- 28 watcher Dart tests, 19 watcher Python tests, formatting and workflow lint pass.
- SDK Pub dry run passes with exactly the four intended exact-pin warnings.
- Hosted-Fleury native CLI core suite passes: 275 tests, 39 TUI PTY cases,
  22 hidden-input boundary cases, hardware simulations, native adapter tests,
  relocation/archive validation and command process replacement checks.
  Receipt: `build/regression/run-3ZvZAs/report.json`. This run started with the
  reviewed changes uncommitted; it records the source digest and that fact.
- No personal vault or physical authenticator was accessed by these checks.

## Release boundaries

Full CI on the final merged main commit, a fresh all-source Actions scan with
assessment, SDK signed tag and served-archive audit remain required. Existing
Apple provider qualification and nonshipping Go-reference maintenance issues
remain bounded follow-ups (#76 and #75); no new device result is implied.
Native CLI release-kit companion packaging, notarized downloaded launch and
installed upgrades remain separate CLI release gates.

The Linux ARM64 Docker CLI suite also passed with the hosted dependencies,
including core, PTY, hardware simulations, archive/ABI checks and genuine
Secret Service command/locked-store flows. Receipt:
`build/regression/run-gqm4Fl/report.json` (inner container report
`run-FXUPCC`). This is not ordinary-user physical USB qualification.

Release-kit successfully completed a private SDK stage on `4ec24cf`, with only
the four deliberate exact-pin warnings. Preserve the existing pub.dev repository
identity (`https://github.com/danReynolds/keybay`); the former subdirectory URL
was correctly refused by RK-PUB-010. Later commits require their own final stage.
The SDK guide's introductory callback wording was also reconciled with the
implemented data-only credential contract; the enrollment/open examples already
used the current API.
