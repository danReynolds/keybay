<!-- keybay-watcher-assessment: {"schema":1,"report_id":"github-32578045777-1","status":"needs_attention","summary":"Watcher infrastructure failed; no vulnerability conclusion was possible and a fixed rerun is required.","actions":[{"label":"Watcher health issue 54","url":"https://github.com/danReynolds/keybay/issues/54"}]} -->

# Assessment

Status: **Needs attention**

## Result

No dependency, platform, or peer applicability conclusion can be drawn from this run. The discovery commands reached their live sources successfully, but checkout removed their relative normalization directory. The artifact publisher therefore received no acceptable inputs and the fail-closed fallback marked every watcher group failed.

This is a monitoring-pipeline failure, not evidence of a Keybay vulnerability and not evidence that Keybay was clear of vulnerabilities at this time.

## Actions

- [Watcher health issue 54](https://github.com/danReynolds/keybay/issues/54) records the failure.
- [PR 53](https://github.com/danReynolds/keybay/pull/53) moves the inputs outside the checkout and adds a regression assertion.
- A complete all-watchers rerun is required after that fix merges.
