"""Check App layer boundaries and the offline Swift source lists."""
from pathlib import Path
import runpy
import tempfile
import unittest

CHECK = runpy.run_path(str(Path(__file__).resolve().parents[1] / "check-architecture.py"))
check_architecture = CHECK["check_architecture"]
declared_types = CHECK["declared_types"]


class ArchitectureTests(unittest.TestCase):
    def setUp(self):
        workspace = tempfile.TemporaryDirectory()
        self.addCleanup(workspace.cleanup)
        self.root = Path(workspace.name)
        self.write("offline-harness/sources.sh", "")

    def write(self, name, content):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        return path

    def test_type_extraction_handles_attributes_and_excludes_private_or_nested_types(self):
        source = """
@MainActor
@Observable internal final class PageModel {
    struct Nested {}
}
@Sendable fileprivate typealias Handler = () -> Void
@available(iOS 26, *)
package actor BackgroundWorker {}
@Observable private final class PrivateModel {}
private
enum AlsoPrivate {}
"""
        self.assertEqual(list(declared_types(source)), ["PageModel", "Handler", "BackgroundWorker"])

    def test_application_and_core_ui_reject_reverse_edges(self):
        self.write("NeoBili/Features/Screen.swift", "@Observable internal final class FeatureScreen {}")
        self.write("NeoBili/Data/Media/Cache.swift", "public actor DiskCache {}")
        self.write("NeoBili/Application/Model.swift", "let page: FeatureScreen")
        self.write("NeoBili/Core/UI/SharedView.swift",
                   "import struct NeoBiliData.SomeExport\nlet page: FeatureScreen\nlet cache: DiskCache")
        errors, _ = check_architecture(self.root)
        self.assertEqual(set(errors), {
            "NeoBili/Application/Model.swift: FeatureScreen crosses the Application boundary",
            "NeoBili/Core/UI/SharedView.swift: FeatureScreen crosses the Core/UI boundary",
            "NeoBili/Core/UI/SharedView.swift: DiskCache crosses the Core/UI boundary",
            "NeoBili/Core/UI/SharedView.swift: NeoBiliData is not an allowed module dependency",
        })

    def test_shared_ui_and_application_can_consume_lower_layers(self):
        self.write("NeoBili/Features/Screen.swift", "private struct LocalState {}")
        self.write("NeoBili/Domain/Value.swift", "public struct DomainValue {}")
        self.write("NeoBili/Application/Model.swift", "import NeoBiliDomain\nstruct LocalState {}")
        self.write("NeoBili/Core/UI/SharedView.swift", "let state: LocalState\nlet value: DomainValue")
        errors, count = check_architecture(self.root)
        self.assertEqual(errors, [])
        self.assertEqual(count, 4)

    def test_project_modules_require_direct_imports_in_app_and_test_sources(self):
        self.write("NeoBili/Application/Model.swift", "// Comment\n\n#if canImport(NeoBiliDomain)\nimport NeoBiliDomain\n#endif")
        self.write("NeoBiliTests/Example.swift", "#if os(iOS) && canImport(NeoBiliCore)\n@testable import NeoBiliCore\n#endif")
        self.write("offline-harness/src/Example.swift", "#if canImport(UIKit)\nimport UIKit\n#endif\nimport NeoBiliData")
        errors, _ = check_architecture(self.root)
        self.assertEqual(errors, [
            "NeoBili/Application/Model.swift:3: import NeoBili modules directly",
            "NeoBiliTests/Example.swift:1: import NeoBili modules directly",
        ])

    def test_missing_harness_paths_include_script_and_line_number(self):
        present = self.write("NeoBili/Application/Current.swift", "struct Current {}")
        self.write("offline-harness/sources.sh",
                   '# "$APP/Application/CommentOnly.swift"\ncp "${APP}/Application/Current.swift" "$BUILD_DIR/"\n')
        self.write("offline-harness/run.sh", 'swiftc "$HARNESS/src/Regression.swift"\n')
        errors, _ = check_architecture(self.root)
        self.assertEqual(errors, ['offline-harness/run.sh:1: missing Swift source "$HARNESS/src/Regression.swift"'])
        self.write("offline-harness/src/Regression.swift", "")
        present.rename(present.with_name("Moved.swift"))
        errors, _ = check_architecture(self.root)
        self.assertEqual(errors, [
            'offline-harness/sources.sh:2: missing Swift source "${APP}/Application/Current.swift"'
        ])
