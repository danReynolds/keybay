---
name: Security sweep
about: Monthly platform-drift and peer review (dispatched via /security-sweep)
title: 'Security sweep: YYYY-MM'
labels: security
---

Monthly sweep — the one manual habit in the security model. Expected outcome
most months: "no applicable findings" in under half an hour. The value is the
guarantee that guidance drift never exceeds one month undetected.

- [ ] Dispatch `/security-sweep` (Claude Code, repo root) and review its
      report — including the **Sources examined** list for coverage holes.
- [ ] Record an applicability decision here for every applicable finding and
      watch item ("applies → action" or "does not apply because …").
- [ ] Confirm the peer-advisory watch and Scorecard runs are green, and that
      any `tool/peer_advisories_seen.json` additions carry their triage.
- [ ] File follow-up issues/PRs for accepted actions, then close this issue.

Annual calibration (one sweep per year): run the sweep cold — no agent —
and compare against the agent's recent reports before closing. Record any
missed finding as a sweep-brief fix in `.claude/commands/security-sweep.md`.
