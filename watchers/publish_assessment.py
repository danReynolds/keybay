"""Publish one reviewed report with GitHub signing; never merge or bypass CI.

Run from the repository root. The default is a read-only publication plan;
--publish explicitly creates the signed commit, updates the report branch with
a lease, and opens/reuses its PR. No private signing key is loaded or copied.
"""

import argparse
import base64
import json
import re
import subprocess
import tempfile
import uuid
from pathlib import Path

from watchers.github import REPOSITORY, api, command, metadata


def require(condition, message):
    if not condition:
        raise ValueError(message)


def git(*args):
    return command("git", *args)


def report_path(paths, run, attempt):
    raw = [p for p in paths if p.endswith("/raw.md")]
    require(len(raw) == 1, "The branch must introduce exactly one raw report")
    path = raw[0].removesuffix("/raw.md")
    require(re.fullmatch(rf"watchers/reports/\d{{4}}-\d{{2}}-\d{{2}}-{run}-{attempt}", path),
            "Report path does not match the requested run")
    require(set(paths) == {path + "/raw.md", path + "/assessment.md", "watchers/reports/SUMMARY.md"},
            "Refusing changes outside this report and its summary")
    return path


def assessment_metadata(text, report_id):
    value = metadata(text, "assessment")
    require(value.get("report_id") == report_id, "Assessment report ID mismatch")
    require(value.get("status") in ("assessed", "needs_attention"), "Assessment is still pending")
    summary = value.get("summary")
    require(isinstance(summary, str) and 0 < len(summary) <= 300 and
            not any(ord(c) < 32 for c in summary), "Invalid assessment summary")
    actions = value.get("actions")
    require(isinstance(actions, list), "Invalid assessment actions")
    for action in actions:
        require(isinstance(action, dict) and isinstance(action.get("label"), str) and
                isinstance(action.get("url"), str) and re.fullmatch(
                    r"https://github\.com/danReynolds/keybay/(issues/[1-9][0-9]*|security/advisories/GHSA-[a-z0-9-]+)",
                    action["url"]), "Action must link to a Keybay issue or private advisory")
    return value


def verified_commit(commit):
    verification = commit["commit"]["verification"]
    require(verification.get("verified") is True and verification.get("reason") == "valid",
            "GitHub did not verify the commit signature")


def prepare(run, attempt, assessment, raw_blob):
    require(re.fullmatch(r"[1-9][0-9]{0,19}", run) and
            re.fullmatch(r"[1-9][0-9]{0,19}", attempt), "Invalid run or attempt")
    require(re.fullmatch(r"[0-9a-f]{40}", raw_blob), "Record the original raw Git blob first")
    branch = f"security-report/{run}-{attempt}"
    git("fetch", "origin", "main", branch)
    base, old = git("rev-parse", "origin/main"), git("rev-parse", "origin/" + branch)
    ancestor = git("merge-base", base, old)
    path = report_path(git("diff", "--name-only", ancestor, old).splitlines(), run, attempt)
    require(git("rev-parse", f"{old}:{path}/raw.md") == raw_blob, "Raw report blob changed")
    require(path + "/raw.md" not in git("ls-tree", "-r", "--name-only", base).splitlines(),
            "This report is already on main")
    # Read bytes without strip()/newline normalization: raw evidence is immutable.
    raw_bytes = subprocess.check_output(["git", "show", f"{old}:{path}/raw.md"])
    raw_metadata = metadata(raw_bytes.decode(), "report")
    report_id = f"github-{run}-{attempt}"
    require(raw_metadata.get("report_id") == report_id and
            raw_metadata.get("run_id") == run and raw_metadata.get("attempt") == attempt,
            "Raw report identity mismatch")
    receipt = api(f"actions/runs/{run}/attempts/{attempt}")
    require(receipt["path"] == ".github/workflows/security-watchers.yml" and
            receipt["head_branch"] == "main" and receipt["status"] == "completed" and
            receipt["event"] in ("schedule", "workflow_dispatch") and
            receipt["event"] == raw_metadata["event"] and
            receipt["head_sha"] == raw_metadata["commit"], "Unexpected Actions provenance")
    original = api(f"commits/{old}")
    marker = f"Keybay-watcher-report: {report_id}"
    if (original.get("author") or {}).get("login") != "github-actions[bot]":
        verified_commit(original)
        require(marker in original["commit"]["message"] and
                f"Raw-blob: {raw_blob}" in original["commit"]["message"],
                "Branch is neither Actions staging nor a verified publisher retry")
    text = Path(assessment).read_text()
    reviewed = assessment_metadata(text, report_id)
    with tempfile.TemporaryDirectory(prefix="keybay-assessment-") as directory:
        reports = Path(directory) / "reports"
        for name in git("ls-tree", "-r", "--name-only", base, "watchers/reports").splitlines():
            target = reports / Path(name).relative_to("watchers/reports")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(subprocess.check_output(["git", "show", f"{base}:{name}"]))
        new = reports / Path(path).name
        new.mkdir(parents=True)
        (new / "raw.md").write_bytes(raw_bytes)
        (new / "assessment.md").write_text(text)
        command("dart", "run", "watchers/report.dart", "summary", "--reports", str(reports),
                "--output", str(reports / "SUMMARY.md"))
        files = {path + "/raw.md": raw_bytes, path + "/assessment.md": text.encode(),
                 "watchers/reports/SUMMARY.md": (reports / "SUMMARY.md").read_bytes()}
    return dict(branch=branch, base=base, old=old, path=path, raw_blob=raw_blob,
                marker=marker, assessment=reviewed, files=files)


def publish(plan):
    branch, base, old = (plan[k] for k in ("branch", "base", "old"))
    files = plan["files"]
    # A previous attempt may have pushed successfully but stopped before the PR.
    same = git("rev-parse", old + "^") == base and all(
        subprocess.check_output(["git", "show", f"{old}:{p}"]) == value for p, value in files.items())
    if same:
        verified_commit(api(f"commits/{old}"))
        head = old
    else:
        staging = f"codex/watcher-assessment-{uuid.uuid4().hex}"
        api("git/refs", {"ref": "refs/heads/" + staging, "sha": base})
        result = api("graphql", {"query": "mutation($input:CreateCommitOnBranchInput!){createCommitOnBranch(input:$input){commit{oid}}}",
            "variables": {"input": {"branch": {"repositoryNameWithOwner": REPOSITORY, "branchName": staging},
                "expectedHeadOid": base, "message": {"headline": "security: assess " + Path(plan["path"]).name,
                    "body": plan["marker"] + "\nRaw-blob: " + plan["raw_blob"] +
                    "\n\nCo-authored-by: github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com>"},
                "fileChanges": {"additions": [{"path": p, "contents": base64.b64encode(b).decode()} for p, b in files.items()]}}}})
        require(not result.get("errors"), "GitHub rejected the signed commit; staging branch retained")
        head = result["data"]["createCommitOnBranch"]["commit"]["oid"]
        verified_commit(api(f"commits/{head}"))
        git("fetch", "origin", staging, "main")
        require(git("rev-parse", "origin/main") == base, "Main advanced; regenerate against the new base")
        require(git("rev-parse", f"{head}:{plan['path']}/raw.md") == plan["raw_blob"], "Signed raw blob mismatch")
        report_path(git("diff", "--name-only", base, head).splitlines(),
                    plan["branch"].split("/")[1].split("-")[0], plan["branch"].rsplit("-", 1)[1])
        git("diff", "--check", base, head)
        git("-c", "credential.helper=!gh auth git-credential", "push",
            f"--force-with-lease=refs/heads/{branch}:{old}", f"https://github.com/{REPOSITORY}.git",
            f"{head}:refs/heads/{branch}")
        api("git/refs/heads/" + staging, method="DELETE")
    body = ("Assess this Actions report against the current Keybay implementation.\n\n"
            f"Disposition: {plan['assessment']['status']}. {plan['assessment']['summary']}\n\n"
            f"Raw evidence is unchanged (`{plan['raw_blob']}`). This verified signed commit changes only "
            "the report and generated summary. Follow-up work remains linked in the assessment; this is not release clearance.\n")
    existing = json.loads(command("gh", "pr", "list", "--repo", REPOSITORY, "--head", branch,
                                  "--state", "open", "--json", "number,url"))
    if existing:
        command("gh", "pr", "edit", str(existing[0]["number"]), "--repo", REPOSITORY,
                "--body-file", "-", input=body)
        url = existing[0]["url"]
    else:
        url = command("gh", "pr", "create", "--repo", REPOSITORY, "--head", branch, "--base", "main",
                      "--title", "Assess security watcher report " + Path(plan["path"]).name[:10],
                      "--body-file", "-", input=body)
    return {"head": head, "url": url, "raw_blob": plan["raw_blob"]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run", required=True)
    parser.add_argument("--attempt", default="1")
    parser.add_argument("--assessment", required=True)
    parser.add_argument("--raw-blob", required=True)
    parser.add_argument("--publish", action="store_true")
    args = parser.parse_args()
    plan = prepare(args.run, args.attempt, args.assessment, args.raw_blob)
    print(json.dumps(publish(plan) if args.publish else
                     {k: v for k, v in plan.items() if k != "files"}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, subprocess.SubprocessError) as error:
        raise SystemExit(f"watcher-publish: {error}")
