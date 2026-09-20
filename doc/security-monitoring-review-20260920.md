# Security monitoring review — September 20, 2026

Discovery and analysis have been running. Publication of three weekly assessments
stalled because the local SSH signing key required an attended unlock. Their
automation logs show completed analysis on August 31, September 7 and September
14, but no committed report or PR. The backlog was subsequently reassessed
against current V2 and merged in PRs #72–74. The fresh September 20 assessment
merged in #77. This is a review of the monitoring program, not a new external
audit of Keybay.

## Discovery runs

| Run | Dependency / platform signals | Peer signals | Result |
| --- | --- | --- | --- |
| [Aug 22, initial](../watchers/reports/2026-08-22-32578045777-1/raw.md) | All sources failed | Unavailable | Infrastructure failure: checkout removed generated inputs. Tracked in #54, fixed and rerun that day. This was never treated as a quiet security result. |
| [Aug 22, rerun](../watchers/reports/2026-08-22-32593631745-1/assessment.md) | Quiet / quiet | 25 | No applicable vulnerability or additional work identified against the implementation at that time. |
| [Aug 24](../watchers/reports/2026-08-24-32702923289-1/assessment.md) | Quiet / quiet | 27 | No applicable finding. 22 exact repeats, two updated sources, three new sources. |
| [Aug 31](../watchers/reports/2026-08-31-33369314477-1/assessment.md) | Quiet / quiet | 42 | No applicable finding after V2 reassessment. 13 repeats, five updated sources, 24 new sources. |
| [Sep 7](../watchers/reports/2026-09-07-34096646506-1/assessment.md) | Quiet / quiet | 38 | No applicable finding after V2 reassessment. 27 repeats, three updated sources, eight new sources. |
| [Sep 14](../watchers/reports/2026-09-14-34819142373-1/assessment.md) | Quiet / quiet | 76 | No applicable finding. Seven repeats, 17 updated sources, 52 new sources. |
| [Sep 20](../watchers/reports/2026-09-20-35525509294-1/assessment.md) | Five dependency signals / one Apple advisory group | 98 | Four Go SSH/OpenPGP advisories prompted #75; the affected packages are not imported by the reference tool and are not shipped with the Dart runtime. The dbus release did not require a security update. Apple custody-related fixes prompted updated-host/device qualification in #76. No additional applicable peer defect was established. |

Peer counts are discovery signals, not vulnerability counts. Comparing every
retained raw report since August 22 gives 306 peer observations across 133
distinct source URLs: 131 exact repeated markers, 42 updated-source markers,
and 133 first-seen sources. The September 20 run alone contains 62 exact
repeats, 15 updated sources and 21 sources not previously seen in that retained
history. These counts use the entire history; counts relative only to the three
backlog reports differ.

A further [verification run](https://github.com/danReynolds/keybay/actions/runs/35540736139)
on September 20 repeats all three discovery sections byte-for-byte. Its 98 peer
signals are all exact repeats, with no new or updated marker. It exercises the
publication repair; these repeated observations are excluded from the totals
above and do not create new follow-up issues.

Reviewed peer failure modes included Android restoration/migration and namespace
deletion; Apple accessibility filtering, shared Keychain groups and delete/add
updates; Linux provider, sandbox and native schema-pointer behavior; and Go
command-protocol parsing. They were useful design comparisons, but many rely on
mechanisms Keybay does not use. A peer bug is not a Keybay bug by association.

## Other checks

- All four weekly CI/fuzz-canary runs from August 24 through September 14
  succeeded. The latest ran the authenticated V2 reader with a fresh random
  seed. No failing input was reported. This is bounded randomized testing,
  not exhaustive proof of parsing or cryptographic correctness.
- All four weekly Scorecard runs succeeded. The open Branch-Protection alert
  reports absent required approvers, stale-review dismissal, code-owner review
  and last-push approval. Successful execution does not mean zero findings;
  these are review-policy decisions, not a demonstrated vault vulnerability.
- OSV scans run on PRs and main code pushes. Four current warnings are tracked
  by #75. The blocking reporter's reachability behavior and the unused imports
  explain why those warnings coexist with a passing check.
- Monthly grouped Dependabot updates cover GitHub Actions. Reviewed maintenance
  PRs have updated pinned actions. The independent core release audit succeeded
  for v0.1.1 on August 25; it is tag-triggered, not a weekly platform test or a
  qualification receipt for the unreleased CLI.

## Value and changes

The dependency and platform watchers are doing useful work: the fresh report
identified specific maintenance and qualification obligations. The peer watcher
is a useful design-review input, but has the highest review cost and substantial
repeat/build/release noise. Keep it, carry forward exact dispositions only while
the relevant Keybay code is unchanged, and review changed signals first. Do not
count repeated signals as new discoveries or permanently suppress entire peers.

The most important observed program defect was stalled follow-through. The
publisher now uses GitHub-verified signing with immutable raw blobs, a narrow
three-file boundary, a current-main base and an exact-head branch lease. Normal
CI still gates merging. The daily health workflow checks scans and merged
assessments independently of the local reviewer, creates one deduplicated issue
for missed scans or reviews overdue by 48 hours, and closes it on recovery.

The recent CLI hidden-input and semantic-disclosure defects were found by the
focused security review and regression tests, not these public-signal watchers.
The watchers complement implementation review, adversarial tests and genuine
platform/distribution qualification. They do not replace them. Production macOS
packaging/notarization, hosted Fleury releases, and the tracked follow-ups remain
separate release work.
