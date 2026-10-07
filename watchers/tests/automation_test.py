import datetime as dt
import json
import subprocess
import unittest
from unittest.mock import patch

from watchers.health import MARKER, TITLE, evaluate, reconcile_issue, verified_recovery
from watchers.github import command, CommandError
from watchers.publish_assessment import assessment_metadata, report_path, verified_commit, publish

NOW = dt.datetime(2026, 9, 20, 12, tzinfo=dt.timezone.utc)


def run(identifier=123, age=dt.timedelta(days=6), conclusion="success"):
    return {"id": identifier, "run_attempt": 1,
            "created_at": (NOW - age).isoformat(), "conclusion": conclusion,
            "status": "completed" if conclusion else "in_progress"}


class HealthTest(unittest.TestCase):
    def test_reviewed_weekly_run_is_healthy(self):
        self.assertEqual(evaluate(NOW, "active", [run()], [], {"github-123-1"}), [])

    def test_new_report_gets_48_hours(self):
        self.assertEqual(evaluate(NOW, "active", [run(age=dt.timedelta(hours=48))], [], set()), [])
        self.assertTrue(evaluate(NOW, "active", [run(age=dt.timedelta(hours=49))], [], set()))

    def test_missing_branch_does_not_hide_unmerged_assessment(self):
        problems = evaluate(NOW, "active", [run()], [], set())
        self.assertEqual(len(problems), 1)
        self.assertIn("github-123-1", problems[0])

    def test_old_manual_branch_is_not_masked_by_fresh_scan(self):
        problems = evaluate(NOW, "active", [run()], [run(456, dt.timedelta(days=50))], {"github-123-1"})
        self.assertEqual(len(problems), 1)
        self.assertIn("github-456-1", problems[0])

    def test_disabled_or_missed_schedule_is_visible(self):
        problems = evaluate(NOW, "disabled_inactivity", [run(age=dt.timedelta(days=9))], [], {"github-123-1"})
        self.assertEqual(len(problems), 3)

    def test_reviewed_manual_recovery_repairs_failure_but_not_missing_schedule(self):
        failed = run(456, dt.timedelta(days=2), "failure")
        recovery = run(789, dt.timedelta(hours=1))
        merged = {"github-123-1", "github-456-1", "github-789-1"}
        old = run(age=dt.timedelta(days=9))
        self.assertEqual(evaluate(NOW, "active", [failed, old], [], merged, [recovery]), [])
        problems = evaluate(NOW, "active", [old], [], merged, [recovery])
        self.assertEqual(problems, ["No scheduled scan started in the last 8 days."])
        self.assertTrue(evaluate(NOW, "disabled_inactivity", [failed], [], merged, [recovery]))

    def test_recovery_must_be_newer_than_failure_and_still_fresh(self):
        failed = run(456, dt.timedelta(hours=1), "failure")
        self.assertTrue(evaluate(NOW, "active", [failed], [], set(), [run(age=dt.timedelta(days=2))]))
        failed = run(456, dt.timedelta(days=10), "failure")
        self.assertTrue(evaluate(NOW, "active", [failed], [], {"github-456-1"}, [run(age=dt.timedelta(days=9))]))

    def test_recovery_requires_exact_successful_all_source_main_run(self):
        raw = {"event": "workflow_dispatch", "run_id": "123", "attempt": "1",
               "report_id": "github-123-1", "commit": "a" * 40,
               "statuses": {"dependencies": "findings", "platforms": "quiet", "peers": "findings"}}
        actual = run() | {"workflow_id": 17, "event": "workflow_dispatch",
                          "head_branch": "main", "head_sha": "a" * 40}
        self.assertTrue(verified_recovery(raw, actual, 17))
        for update in [{"workflow_id": 18}, {"event": "pull_request"}, {"head_branch": "feature"},
                       {"conclusion": "failure"}, {"status": "in_progress"}, {"id": 456},
                       {"run_attempt": 2}, {"head_sha": "b" * 40}]:
            self.assertFalse(verified_recovery(raw, actual | update, 17))
        for status in ("failed", "not_run"):
            self.assertFalse(verified_recovery(raw | {"statuses": raw["statuses"] | {"platforms": status}}, actual, 17))
        self.assertFalse(verified_recovery(raw | {"statuses": {"dependencies": "quiet"}}, actual, 17))

    def test_recent_failed_run_not_masked_by_previous_success(self):
        problems = evaluate(NOW, "active", [run(456, dt.timedelta(hours=1), "failure"), run()], [], {"github-123-1"})
        self.assertEqual(len(problems), 1)
        self.assertIn("did not succeed", problems[0])

    def test_stuck_run_is_visible(self):
        problems = evaluate(NOW, "active", [run(456, dt.timedelta(hours=7), None), run()], [], {"github-123-1"})
        self.assertEqual(len(problems), 1)
        self.assertIn("6 hours", problems[0])

    def test_issue_lifecycle_deduplicates_and_recovers(self):
        calls = []
        def mutate(path, body, **options):
            calls.append((path, body, options))
        reconcile_issue(["Scan overdue."], [], mutate)
        self.assertEqual(calls[-1][0], "issues")
        existing = {"number": 9, "state": "open", "body": calls[-1][1]["body"],
                    "title": TITLE, "user": {"login": "github-actions[bot]"}}
        calls.clear()
        reconcile_issue(["Scan overdue."], [existing], mutate)
        self.assertEqual(calls, [])
        reconcile_issue([], [existing], mutate)
        self.assertEqual(calls[-1][1]["state"], "closed")
        existing["state"] = "closed"
        reconcile_issue(["Scan overdue."], [existing], mutate)
        self.assertEqual(calls[-1][1]["state"], "open")

    def test_duplicate_health_issues_fail_without_writing(self):
        issue = {"body": MARKER, "title": TITLE, "user": {"login": "github-actions[bot]"}}
        with self.assertRaises(ValueError):
            reconcile_issue([], [issue, issue], lambda *a: self.fail())

    def test_untrusted_issue_cannot_impersonate_health_monitor(self):
        issue = {"number": 9, "state": "open", "body": MARKER, "title": TITLE,
                 "user": {"login": "untrusted-contributor"}}
        calls = []
        reconcile_issue(["Scan overdue."], [issue], lambda *a: calls.append(a))
        self.assertEqual(calls[0][0], "issues")


class PublicationBoundaryTest(unittest.TestCase):
    def setUp(self):
        self.path = "watchers/reports/2026-09-20-123-1"
        self.paths = [self.path + "/raw.md", self.path + "/assessment.md", "watchers/reports/SUMMARY.md"]

    def test_unrelated_or_different_run_change_is_rejected(self):
        self.assertEqual(report_path(self.paths, "123", "1"), self.path)
        for paths in [self.paths + ["lib/secret.dart"], [p.replace("123", "456") for p in self.paths]]:
            with self.assertRaises(ValueError):
                report_path(paths, "123", "1")

    def test_pending_mismatched_or_external_assessment_is_rejected(self):
        valid = {"schema": 1, "report_id": "github-123-1", "status": "needs_attention",
                 "summary": "Follow-up tracked.", "actions": [{"label": "Follow-up", "url": "https://github.com/danReynolds/keybay/issues/75"}]}
        def text(value):
            return "<!-- keybay-watcher-assessment: " + json.dumps(value) + " -->\n"
        self.assertEqual(assessment_metadata(text(valid), "github-123-1"), valid)
        for update in [{"status": "pending"}, {"report_id": "github-456-1"},
                       {"actions": [{"label": "outside", "url": "https://example.com/issue"}]}]:
            with self.assertRaises(ValueError):
                assessment_metadata(text(valid | update), "github-123-1")

    def test_unverified_signature_is_rejected(self):
        with self.assertRaises(ValueError):
            verified_commit({"commit": {"verification": {"verified": False, "reason": "unsigned"}}})

    def test_command_failure_explains_permission_without_echoing_request(self):
        error = subprocess.CalledProcessError(1, ("gh", "api", "graphql"),
                                              output="private response", stderr="gh: FORBIDDEN")
        with patch("watchers.github.subprocess.run", side_effect=error):
            with self.assertRaises(CommandError) as raised:
                command("gh", "api", "graphql", input="private request")
        self.assertIn("FORBIDDEN", str(raised.exception))
        self.assertNotIn("private", str(raised.exception))

    def test_main_advance_prevents_report_push(self):
        plan = dict(branch="security-report/123-1", base="old-main", old="staging", path=self.path,
                    raw_blob="a" * 40, marker="Keybay-watcher-report: github-123-1", files={p: b"x" for p in self.paths})
        git_calls = []
        def fake_git(*args):
            git_calls.append(args)
            if args == ("rev-parse", "staging^"):
                return "older-main"
            if args == ("rev-parse", "origin/main"):
                return "new-main"
            return ""
        def fake_api(path, *args, **kwargs):
            if path == "graphql":
                return {"data": {"createCommitOnBranch": {"commit": {"oid": "signed"}}}}
            if path.startswith("commits/"):
                return {"commit": {"verification": {"verified": True, "reason": "valid"}}}
        with patch("watchers.publish_assessment.git", fake_git), patch("watchers.publish_assessment.api", fake_api):
            with self.assertRaisesRegex(ValueError, "Main advanced"):
                publish(plan)
        self.assertFalse(any("push" in args for args in git_calls))

    def test_publication_uses_lease_and_opens_pr_without_merging(self):
        plan = dict(branch="security-report/123-1", base="main", old="staging", path=self.path,
                    raw_blob="a" * 40, marker="Keybay-watcher-report: github-123-1",
                    assessment={"status": "assessed", "summary": "No applicable finding."},
                    files={p: b"x" for p in self.paths})
        git_calls, commands = [], []
        def fake_git(*args):
            git_calls.append(args)
            if args == ("rev-parse", "staging^"):
                return "older-main"
            if args == ("rev-parse", "origin/main"):
                return "main"
            if args == ("rev-parse", "signed:" + self.path + "/raw.md"):
                return "a" * 40
            if args[:2] == ("diff", "--name-only"):
                return "\n".join(self.paths)
            return ""
        def fake_api(path, *args, **kwargs):
            if path == "graphql":
                return {"data": {"createCommitOnBranch": {"commit": {"oid": "signed"}}}}
            if path.startswith("commits/"):
                return {"commit": {"verification": {"verified": True, "reason": "valid"}}}
        def fake_command(*args, **kwargs):
            commands.append(args)
            return "[]" if args[:3] == ("gh", "pr", "list") else "https://github.com/danReynolds/keybay/pull/1"
        with patch("watchers.publish_assessment.git", fake_git), patch("watchers.publish_assessment.api", fake_api), patch("watchers.publish_assessment.command", fake_command):
            self.assertEqual(publish(plan)["head"], "signed")
        pushes = [args for args in git_calls if "push" in args]
        self.assertEqual(len(pushes), 1)
        self.assertIn("--force-with-lease=refs/heads/security-report/123-1:staging", pushes[0])
        self.assertEqual(pushes[0][-1], "signed:refs/heads/security-report/123-1")
        self.assertFalse(any("merge" in args for args in commands))


if __name__ == "__main__":
    unittest.main()
