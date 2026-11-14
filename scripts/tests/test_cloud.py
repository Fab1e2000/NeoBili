"""Cloud hooks fail closed and release retries preserve published artifacts."""
import importlib.util
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("cloud_release", ROOT / "ci_scripts/release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
gateway_spec = importlib.util.spec_from_file_location("cloud_gateway", ROOT / "scripts/xcode_cloud.py")
gateway = importlib.util.module_from_spec(gateway_spec)
gateway_spec.loader.exec_module(gateway)


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "NeoBili").mkdir()
        self.info = {"CFBundleShortVersionString": "1.3.2", "CFBundleVersion": "19"}
        (self.root / "NeoBili/Info.plist").write_bytes(plistlib.dumps(self.info))
        (self.root / "docs/releases").mkdir(parents=True)
        (self.root / "docs/releases/v1.3.2.md").write_text("# NeoBili 1.3.2\nRelease notes\n")
        self.env = {"CI_COMMIT": "a" * 40, "CI_BUILD_NUMBER": "12",
                    "CI_BUILD_URL": "https://appstoreconnect.apple.com/build/example"}

    def test_manual_draft_is_separate_from_version_release(self):
        details, _ = release.metadata(self.root, self.env)
        self.assertEqual(details["tag_name"], "cloud-build-12")
        self.assertTrue(details["draft"])
        self.assertTrue(details["prerelease"])
        self.assertIn(self.env["CI_COMMIT"], details["body"])

    def test_versioned_draft_uses_notes_and_exact_commit(self):
        details, _ = release.metadata(self.root, dict(self.env, CI_TAG="v1.3.2"))
        self.assertEqual(details["name"], "NeoBili 1.3.2")
        self.assertFalse(details["prerelease"])
        self.assertIn("Release notes", details["body"])
        self.assertEqual(details["target_commitish"], "a" * 40)

    def test_tag_mismatch_and_pr_are_rejected(self):
        for extra in ({"CI_TAG": "v1.3.3"}, {"CI_PULL_REQUEST_NUMBER": "42"}):
            with self.subTest(extra=extra), self.assertRaises(ValueError):
                release.metadata(self.root, dict(self.env, **extra))

    @patch.object(release, "request")
    def test_existing_public_release_is_never_mutated(self, request):
        details, _ = release.metadata(self.root, self.env)
        request.return_value = [{"tag_name": details["tag_name"], "draft": False}]
        with self.assertRaisesRegex(ValueError, "already public"):
            release.publish("test", details, [], False)
        self.assertEqual([call.args[1] for call in request.call_args_list], ["GET"])

    @patch.object(release, "request")
    def test_tag_moved_to_another_commit_is_rejected(self, request):
        details, _ = release.metadata(self.root, dict(self.env, CI_TAG="v1.3.2"))
        request.return_value = {"sha": "b" * 40}
        with self.assertRaisesRegex(ValueError, "different commit"):
            release.check_release("test", details, True)

    @patch.object(release, "request")
    def test_draft_for_another_commit_is_preserved(self, request):
        details, _ = release.metadata(self.root, self.env)
        request.return_value = [dict(details, target_commitish="b" * 40)]
        with self.assertRaisesRegex(ValueError, "another commit"):
            release.publish("test", details, [], False)
        self.assertEqual(request.call_count, 1)

    @patch.object(release, "request")
    def test_retry_replaces_only_matching_assets_and_keeps_draft(self, request):
        details, _ = release.metadata(self.root, self.env)
        existing = dict(details, id=9, html_url="https://github.com/example/draft",
                        upload_url="https://uploads.github.com/repos/example/releases/9/assets{?name}",
                        assets=[{"id": 10, "name": "app.ipa"}, {"id": 11, "name": "extra.txt"}])
        request.side_effect = [[existing], existing, None, {"id": 12}]
        ipa = self.root / "app.ipa"
        ipa.write_bytes(b"fixture")
        release.publish("test", details, [ipa], False)
        calls = request.call_args_list
        self.assertEqual([call.args[1] for call in calls], ["GET", "PATCH", "DELETE", "POST"])
        self.assertTrue(calls[1].args[3]["draft"])
        self.assertEqual(calls[2].args[2], "/releases/assets/10")

    @patch.object(release.subprocess, "run")
    def test_package_removes_provisioning_restores_build_and_preserves_source(self, run):
        app = self.root / "built/NeoBili.app"
        app.mkdir(parents=True)
        (app / "Info.plist").write_bytes(plistlib.dumps(dict(self.info, CFBundleVersion="200")))
        (app / "embedded.mobileprovision").write_text("private fixture")
        (app / "NeoBili").write_bytes(b"fixture")
        captured = {}

        def invoke(args, **kwargs):
            if args[0] == "zip":
                copied = Path(kwargs["cwd"]) / "Payload/NeoBili.app"
                captured["info"] = plistlib.loads((copied / "Info.plist").read_bytes())
                captured["profile"] = (copied / "embedded.mobileprovision").exists()
                Path(args[2]).write_bytes(b"packaged fixture")
            return subprocess.CompletedProcess(args, 0)

        run.side_effect = invoke
        files = release.package(app, self.root / "output", self.info)
        self.assertEqual(captured["info"]["CFBundleVersion"], "19")
        self.assertFalse(captured["profile"])
        self.assertTrue((app / "embedded.mobileprovision").exists())
        self.assertEqual(files[0].name, "NeoBili-v1.3.2-unsigned.ipa")
        self.assertIn(files[0].name, files[1].read_text())


class CloudHookTests(unittest.TestCase):
    def run_hook(self, hook, **values):
        env = {key: value for key, value in os.environ.items() if not key.startswith("CI_")}
        env.update(values)
        return subprocess.run(["bash", str(ROOT / "ci_scripts" / hook)], env=env,
                              capture_output=True, text=True)

    def test_failed_build_never_uploads(self):
        result = self.run_hook("ci_post_xcodebuild.sh", CI_WORKFLOW="Release",
                               CI_XCODEBUILD_ACTION="build", CI_XCODEBUILD_EXIT_CODE="65")
        self.assertEqual(result.returncode, 65)

    def test_unknown_workflow_fails(self):
        result = self.run_hook("ci_pre_xcodebuild.sh", CI_WORKFLOW="Typo", CI_XCODEBUILD_ACTION="build")
        self.assertNotEqual(result.returncode, 0)

    def test_test_runner_needs_no_source_checkout_or_release_credentials(self):
        result = self.run_hook("ci_pre_xcodebuild.sh", CI_WORKFLOW="Build",
                               CI_XCODEBUILD_ACTION="test-without-building")
        self.assertEqual(result.returncode, 0, result.stderr)


class ApprovalGatewayTests(unittest.TestCase):
    def test_changed_source_or_target_is_rejected(self):
        attributes = {"executionProgress": "COMPLETE", "sourceCommit": {"commitSha": "source"},
                      "destinationCommit": {"commitSha": "target"}}
        gateway.validate_commits(attributes, "source", "target")
        for source, target in (("changed", "target"), ("source", "changed")):
            with self.assertRaises(ValueError):
                gateway.validate_commits(attributes, source, target)

    def test_completed_build_without_commit_cannot_pass(self):
        with self.assertRaises(ValueError):
            gateway.validate_commits({"executionProgress": "COMPLETE"}, "source")

    def test_pending_cloud_build_waits_for_checkout_commit(self):
        attributes = {"executionProgress": "PENDING", "sourceCommit": {"commitSha": ""}}
        gateway.validate_commits(attributes, "source")
        attributes["executionProgress"] = "COMPLETE"
        with self.assertRaises(ValueError):
            gateway.validate_commits(attributes, "source")

    def test_completed_pr_requires_target_commit(self):
        with self.assertRaises(ValueError):
            gateway.validate_commits({"executionProgress": "COMPLETE", "sourceCommit": {"commitSha": "source"}},
                                     "source", "target")

    def test_pr_lookup_uses_open_pull_request_including_forks(self):
        from unittest.mock import Mock
        cloud = Mock(return_value={"data": [{"id": "pr-id", "attributes": {"number": 42, "isClosed": False}}]})
        value = gateway.build_relationships(cloud, "workflow", "repo", {"pull_request": {"number": 42}}, "refs/heads/main")
        self.assertEqual(value["pullRequest"]["data"], {"type": "scmPullRequests", "id": "pr-id"})
        self.assertNotIn("sourceBranchOrTag", value)

    def test_manual_lookup_uses_exact_ref_and_paginates(self):
        from unittest.mock import Mock
        cloud = Mock(side_effect=[
            {"data": [], "links": {"next": "/next"}},
            {"data": [{"id": "branch-id", "attributes": {"canonicalName": "refs/heads/develop", "isDeleted": False}}]},
        ])
        value = gateway.build_relationships(cloud, "workflow", "repo", {}, "refs/heads/develop")
        self.assertEqual(value["sourceBranchOrTag"]["data"]["id"], "branch-id")

    def test_absent_cloud_resource_fails_before_starting_build(self):
        from unittest.mock import Mock
        cloud = Mock(return_value={"data": []})
        with self.assertRaises(ValueError):
            gateway.build_relationships(cloud, "workflow", "repo", {}, "refs/heads/develop")
        self.assertEqual(cloud.call_count, 1)


if __name__ == "__main__":
    unittest.main()
