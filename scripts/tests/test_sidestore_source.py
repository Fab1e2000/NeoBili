"""The SideStore source stays aligned with a published unsigned release."""
from pathlib import Path
import importlib.util
import json
import subprocess
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("sidestore_source", ROOT / "scripts" / "sidestore_source.py")
source = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(source)


class SideStoreSourceTests(unittest.TestCase):
    def test_changelog_omits_title_and_install_section(self):
        notes = "# 标题\n\n## 外观\n\n- 一项\n\n## 安装\n\n自行签名\n"
        self.assertEqual(source.changelog(notes), "## 外观\n\n- 一项")

    def test_source_points_at_the_unsigned_release(self):
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
        self.assertEqual(payload, source.build_source(tag, app["size"], app["versionDate"], notes))
        self.assertEqual(path.read_text(), source.dumps(payload))
