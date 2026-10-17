"""Exercise validation routing and failure propagation in an isolated checkout."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ValidationWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for folder in ("scripts/tests", "offline-harness", ".githooks", "bin"):
            (self.root / folder).mkdir(parents=True)
        for file in ("scripts/verify.sh", ".githooks/pre-push"):
            shutil.copyfile(ROOT / file, self.root / file)
        # Python 3.14 treats empty unittest discovery as a failure. The nested
        # quick fixture needs one inert test, rather than depending on that exit code.
        (self.root / "scripts/tests/test_verify.py").write_text(
            "import unittest\n"
            "class FixtureSmokeTest(unittest.TestCase):\n"
            "    def test_fixture(self):\n"
            "        pass\n"
        )
        self.env = dict(os.environ, CALL_LOG=str(self.root / "calls"))
        self.env["PATH"] = str(self.root / "bin") + os.pathsep + self.env["PATH"]
        # The fixture has no Swift or Xcode dependency; only orchestration runs.
        launcher = self.root / "bin/zsh"
        launcher.write_text('#!/bin/bash\nexec bash "$@"\n')
        launcher.chmod(0o755)
        for name in ("architecture", "doc-links"):
            (self.root / f"scripts/check-{name}.py").write_text(
                "import os\n"
                f"raise SystemExit(int(os.environ.get('{name.upper()}_STATUS', '0')))\n"
            )
        for file, name in (("offline-harness/run.sh", "offline"),
                           ("offline-harness/performance.sh", "performance"),
                           ("scripts/simulator.sh", "simulator")):
            (self.root / file).write_text(
                f'printf "%s\\n" "{name} $*" >> "$CALL_LOG"\n'
                f'exit "${{{name.upper()}_STATUS:-0}}"\n'
            )
        self.git("init", "-q")
        self.git("-c", "user.name=Workflow Test", "-c", "user.email=test@example.invalid",
                 "commit", "--allow-empty", "-qm", "fixture")

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.root, env=self.env,
                              check=True, capture_output=True, text=True)

    def run_verify(self, *args):
        return subprocess.run(["bash", str(self.root / "scripts/verify.sh"), *args],
                              cwd=self.root.parent, env=self.env,
                              capture_output=True, text=True, timeout=20)

    def calls(self):
        path = self.root / "calls"
        return path.read_text().splitlines() if path.exists() else []

    def summary(self):
        return next(self.root.glob("DerivedData/Validation/*/summary.tsv")).read_text()

    def test_quick_does_not_run_regression(self):
        result = self.run_verify("quick")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.calls(), [])
        self.assertIn("architecture\tpassed", self.summary())
        self.assertIn("staged-diff\tpassed", self.summary())

    def test_quick_failure_is_reported_and_other_checks_continue(self):
        self.env["ARCHITECTURE_STATUS"] = "7"
        result = self.run_verify("quick")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("architecture\tfailed\t7", self.summary())
        self.assertIn("documentation\tpassed", self.summary())

    def test_staged_whitespace_blocks_quick(self):
        (self.root / "example.txt").write_text("trailing space \n")
        self.git("add", "example.txt")
        result = self.run_verify("quick")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("staged-diff\tfailed", self.summary())

    def test_full_runs_both_stages_after_offline_failure(self):
        self.env["OFFLINE_STATUS"] = "9"
        result = self.run_verify("full")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), ["offline ", "simulator test"])
        self.assertIn("offline\tfailed\t9", self.summary())
        self.assertIn("simulator\tpassed", self.summary())

    def test_full_propagates_simulator_failure(self):
        self.env["SIMULATOR_STATUS"] = "65"
        self.assertNotEqual(self.run_verify("full").returncode, 0)
        self.assertIn("simulator\tfailed\t65", self.summary())

    def test_targeted_preserves_multiple_selectors(self):
        result = self.run_verify("targeted", "AccountSessionTests", "OtherTests/testExample")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), ["simulator test AccountSessionTests OtherTests/testExample"])

    def test_invalid_arguments_do_not_run_checks(self):
        for args in (("targeted",), ("targeted", "-only-testing:Other"),
                     ("targeted", "Tests/test;echo"), ("full", "Tests"), ("unknown",)):
            with self.subTest(args=args):
                self.assertEqual(self.run_verify(*args).returncode, 2)
        self.assertEqual(self.calls(), [])
        self.assertFalse((self.root / "DerivedData").exists())

    def test_explicit_modes_route_to_specialists(self):
        for mode in ("offline", "network", "performance"):
            self.assertEqual(self.run_verify(mode).returncode, 0)
        self.assertEqual(self.calls(), ["offline ", "simulator network", "performance "])

    def test_hook_consumes_git_input_and_propagates_failure(self):
        (self.root / "scripts/verify.sh").write_text(
            '[[ "$1" == quick ]] || exit 8\n'
            'if read -r line; then exit 9; fi\n'
            'exit "${QUICK_STATUS:-0}"\n'
        )
        for status in ("0", "1"):
            self.env["QUICK_STATUS"] = status
            result = subprocess.run(["bash", ".githooks/pre-push"], cwd=self.root,
                                    env=self.env, input="refs/heads/test sha ref sha\n",
                                    capture_output=True, text=True, timeout=20)
            self.assertEqual(result.returncode, int(status), result.stdout + result.stderr)


class SimulatorArgumentTests(unittest.TestCase):
    def test_extra_arguments_keep_boundaries_and_default_invocation_works(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            (root / "bin").mkdir()
            shutil.copyfile(ROOT / "scripts/simulator.sh", root / "scripts/simulator.sh")
            xcrun = root / "bin/xcrun"
            xcrun.write_text("#!/bin/bash\necho '{\"devices\":{\"com.apple.CoreSimulator.SimRuntime.iOS-27-0\":[{\"name\":\"iPhone 18 Pro\",\"udid\":\"fixture\",\"isAvailable\":true}]}}'\n")
            xcrun.chmod(0o755)
            xcode = root / "bin/xcodebuild"
            xcode.write_text('#!/bin/bash\n[[ "$1" == -version ]] && exit 0\nprintf "%s\\n" "$@" > "$CALL_LOG"\nexit 17\n')
            xcode.chmod(0o755)
            env = dict(os.environ, PATH=str(root / "bin") + os.pathsep + os.environ["PATH"],
                       TMPDIR=directory, CALL_LOG=str(root / "calls"))
            for arguments in ([], ["SomeTests", "--", "-enableThreadSanitizer", "YES", "OTHER_SWIFT_FLAGS=a b"]):
                result = subprocess.run(["bash", str(root / "scripts/simulator.sh"), "test", *arguments],
                                        env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 17, result.stdout + result.stderr)
                calls = (root / "calls").read_text().splitlines()
                self.assertIn("CODE_SIGNING_ALLOWED=NO", calls)
                if arguments:
                    self.assertIn("OTHER_SWIFT_FLAGS=a b", calls)
                    self.assertIn("-only-testing:NeoBiliTests/SomeTests", calls)
                self.assertFalse((root / "neobili-simulator-fixture.lock").exists())


if __name__ == "__main__":
    unittest.main()
