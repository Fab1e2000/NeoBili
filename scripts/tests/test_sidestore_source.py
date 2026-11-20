"""The SideStore source stays aligned with a published unsigned release."""
from pathlib import Path
import importlib.util
import json
import plistlib
import re
import subprocess
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("sidestore_source", ROOT / "scripts" / "sidestore_source.py")
source = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(source)


class SideStoreSourceTests(unittest.TestCase):
    def test_workflow_uploads_the_current_project_icon(self):
        workflow = (ROOT / ".github/workflows/sidestore.yml").read_text()
        upload = re.search(r" put-icon\s*<\s*(\S+)", workflow)
        self.assertIsNotNone(upload)
        icon = ROOT / upload[1]
        self.assertIn(f'src="{upload[1]}"', (ROOT / "README.md").read_text())
        self.assertEqual(icon.read_bytes()[:8], b"\x89PNG\r\n\x1a\n")

    def test_changelog_omits_title_and_install_section(self):
        notes = "# 标题\n\n## 外观\n\n- 一项\n\n## 安装\n\n自行签名\n"
        self.assertEqual(source.changelog(notes), "## 外观\n\n- 一项")

    def test_permissions_come_from_the_requested_release(self):
        info = plistlib.loads((ROOT / "NeoBili/Info.plist").read_bytes())
        audio = {"type": "background-audio", "usageDescription": "在后台继续播放视频和直播。"}
        for tag, plist, expected in [
            ("v2.0.0", info, [audio]),
            ("v1.0.0", {**info, "NSPhotoLibraryAddUsageDescription": "保存二维码"},
             [audio, {"type": "photos", "usageDescription": "保存二维码"}]),
        ]:
            with self.subTest(tag=tag), patch.object(source.subprocess, "run") as run:
                run.return_value = subprocess.CompletedProcess([], 0, stdout=plistlib.dumps(plist))
                self.assertEqual(source.release_permissions(tag), expected)
                self.assertEqual(run.call_args.args[0], ["git", "show", f"refs/tags/{tag}:NeoBili/Info.plist"])

    @patch.object(source, "release_permissions", return_value=[])
    def test_source_points_at_the_unsigned_release(self, permissions):
        payload = source.build_source(
            "v1.2.3", 10, "2026-01-02T03:04:05Z", "# 标题\n\n## 变化\n\n- 一处\n")
        app = payload["apps"][0]
        self.assertEqual(payload["sourceURL"], source.SOURCE_URL)
        self.assertEqual(app["bundleIdentifier"], "com.elsterlee.NeoBili")
        self.assertEqual(app["version"], "1.2.3")
        self.assertEqual(app["size"], 10)
        self.assertEqual(app["versions"], [{
            "version": "1.2.3",
            "date": "2026-01-02T03:04:05Z",
            "localizedDescription": "## 变化\n\n- 一处",
            "downloadURL": app["downloadURL"],
            "size": 10,
        }])
        self.assertEqual(
            app["downloadURL"], "https://n015.top/neobili/NeoBili-v1.2.3-unsigned.ipa")
        self.assertNotIn("安装", app["versionDescription"])
        permissions.assert_called_once_with("v1.2.3")

    def test_rejects_unpublished_or_incomplete_inputs(self):
        notes = "# 标题\n\n## 变化\n\n- 一处\n"
        with self.assertRaises(ValueError):
            source.build_source("1.2.3", 10, "2026-01-02T03:04:05Z", notes)
        with self.assertRaises(ValueError):
            source.build_source("v1.2.3", 0, "2026-01-02T03:04:05Z", notes)
        with self.assertRaises(ValueError):
            source.build_source("v1.2.3", 10, "yesterday", notes)

    def test_github_release_rejects_a_draft(self):
        completed = subprocess.CompletedProcess(
            args=[], returncode=0,
            stdout=json.dumps({
                "isDraft": True,
                "publishedAt": "2026-01-02T03:04:05Z",
                "assets": [],
            }),
            stderr="",
        )
        with patch.object(source.subprocess, "run", return_value=completed):
            with self.assertRaises(ValueError) as raised:
                source.github_release("v1.2.3")
        self.assertIn("草稿", str(raised.exception))

    def test_committed_source_matches_its_release_notes(self):
        path = ROOT / "sidestore" / "apps.json"
        payload = json.loads(path.read_text())
        app = payload["apps"][0]
        tag = "v" + app["version"]
        notes = (ROOT / "docs" / "releases" / f"{tag}.md").read_text()
        # A shallow test checkout can lack the published tag.
        with patch.object(source, "release_permissions", return_value=app["permissions"]):
            self.assertEqual(payload, source.build_source(tag, app["size"], app["versionDate"], notes))
        self.assertEqual(path.read_text(), source.dumps(payload))
