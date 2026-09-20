"""Check discovery and assessment freshness independently of the local reviewer."""

import argparse
import datetime as dt
import json
import re
import subprocess

from watchers.github import REPOSITORY, api, command, metadata, pages

MARKER = "<!-- keybay-watcher-health:v1 -->"
TITLE = "Watcher health: monitoring or assessments are overdue"
SCAN_LIMIT = dt.timedelta(days=8)
ASSESSMENT_LIMIT = dt.timedelta(hours=48)
RUN_LIMIT = dt.timedelta(hours=6)


def timestamp(value):
    parsed = dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("Health timestamp has no timezone")
    return parsed


def evaluate(now, workflow_state, runs, pending, merged):
    """Use Actions timestamps, never the age of a rewritten Git commit."""
    problems = []
    if workflow_state != "active":
        problems.append("Security watcher workflow is not active.")
    scheduled = sorted(runs, key=lambda run: timestamp(run["created_at"]), reverse=True)
    successful = [run for run in scheduled if run["conclusion"] == "success"]
    if not successful or now - timestamp(successful[0]["created_at"]) > SCAN_LIMIT:
        problems.append("No successful scheduled all-source scan in the last 8 days.")
    if scheduled:
        latest = scheduled[0]
        age = now - timestamp(latest["created_at"])
        if latest["status"] == "completed" and latest["conclusion"] != "success":
            problems.append(f"Latest scheduled scan did not succeed: run {latest['id']}.")
        elif latest["status"] != "completed" and age > RUN_LIMIT:
            problems.append(f"Scheduled scan has not completed within 6 hours: run {latest['id']}.")
    overdue = set()
    # Check recent scheduled runs even if their staging branch was lost/deleted.
    for run in scheduled:
        age = now - timestamp(run["created_at"])
        identity = f"github-{run['id']}-{run['run_attempt']}"
        if ASSESSMENT_LIMIT < age <= dt.timedelta(days=35) and identity not in merged:
            overdue.add(identity)
    # Also catch old/manual branches, regardless of the successful scan cadence.
    for run in pending:
        identity = f"github-{run['id']}-{run['run_attempt']}"
        if now - timestamp(run["created_at"]) > ASSESSMENT_LIMIT and identity not in merged:
            overdue.add(identity)
    problems.extend(f"Assessment has not reached main within 48 hours: {identity}." for identity in sorted(overdue))
    return problems


def collect():
    workflow = api("actions/workflows/security-watchers.yml")
    runs = api("actions/workflows/security-watchers.yml/runs?event=schedule&per_page=100")["workflow_runs"]
    refs = list(pages("git/matching-refs/heads/security-report/"))
    pending = []
    for ref in refs:
        match = re.fullmatch(r"refs/heads/security-report/([1-9][0-9]*)-([1-9][0-9]*)", ref["ref"])
        if not match:
            raise ValueError("Invalid report branch")
        run, attempt = match.groups()
        pending.append(api(f"actions/runs/{run}/attempts/{attempt}"))
    # Refresh only a tracking ref. The user's checkout and edits stay untouched.
    command("git", "fetch", "origin", "main")
    paths = command("git", "ls-tree", "-r", "--name-only", "origin/main", "watchers/reports").splitlines()
    merged = set()
    for path in paths:
        if path.endswith("/assessment.md"):
            value = metadata(command("git", "show", "origin/main:" + path), "assessment")
            raw = metadata(command("git", "show", "origin/main:" + path.replace("assessment.md", "raw.md")), "report")
            if value.get("report_id") != raw.get("report_id"):
                raise ValueError("Merged assessment identity mismatch")
            if value.get("status") in ("assessed", "needs_attention"):
                merged.add(value["report_id"])
    return workflow["state"], runs, pending, merged


def reconcile_issue(problems, issues, mutate=api):
    """One stable issue; update only on a changed condition, close on recovery."""
    matches = [issue for issue in issues if MARKER in (issue.get("body") or "") and
               issue.get("title") == TITLE and "pull_request" not in issue and
               (issue.get("user") or {}).get("login") in ("github-actions[bot]", "danReynolds")]
    if len(matches) > 1:
        raise ValueError("Duplicate watcher-health issues require review")
    existing = matches[0] if matches else None
    if problems:
        body = (MARKER + "\n\nSecurity monitoring needs attention:\n\n" +
                "\n".join("- " + problem for problem in problems) +
                "\n\nInspect the [health workflow](https://github.com/" + REPOSITORY +
                "/actions/workflows/watcher-health.yml) and the pending report PRs. "
                "This is a monitoring-health alert, not a vulnerability claim.\n")
        if existing is None:
            return mutate("issues", {"title": TITLE, "body": body})
        if existing["state"] != "open" or existing["body"] != body:
            return mutate(f"issues/{existing['number']}", {"state": "open", "body": body}, method="PATCH")
    elif existing is not None and existing["state"] == "open":
        return mutate(f"issues/{existing['number']}", {"state": "closed", "state_reason": "completed"}, method="PATCH")
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--update-issue", action="store_true", help="Reconcile the single public health issue")
    args = parser.parse_args()
    try:
        state, runs, pending, merged = collect()
        problems = evaluate(dt.datetime.now(dt.timezone.utc), state, runs, pending, merged)
    except (ValueError, KeyError, subprocess.SubprocessError):
        # Do not publish arbitrary API/error text or raw report content.
        problems = ["Health check could not read or validate its inputs; inspect the failed workflow."]
    print(json.dumps({"healthy": not problems, "problems": problems}, indent=2))
    if args.update_issue:
        reconcile_issue(problems, list(pages("issues?state=all")))
    return 1 if problems else 0


if __name__ == "__main__":
    raise SystemExit(main())
