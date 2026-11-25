#!/usr/bin/env python3
"""Check source-layer dependencies without importing or executing application code."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN = {
    "Domain": {"Features", "Application", "Data", "Core", "Platform"},
    "Data": {"Features", "Application"},
    "Features": {"Data"},
    "Application": {"Data", "Features"},
    "Core/UI": {"Data", "Features"},
}

ATTRIBUTE = r"@\w+(?:\.\w+)*(?:\([^\n]*?\))?"
TYPE_DECLARATION = re.compile(
    rf"^(?P<modifiers>(?:(?:{ATTRIBUTE}|"
    r"private|fileprivate|internal|package|public|open|final|nonisolated|indirect|distributed)"
    r"(?:[ \t]+|\r?\n))*)(?:struct|class|actor|enum|protocol|typealias)\s+(?P<name>\w+)",
    re.M,
)
MODULE_IMPORT = re.compile(r"\bimport\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?(NeoBili\w*)\b")
PROJECT_IMPORT_GUARD = re.compile(r"^\s*#(?:if|elseif)\b[^\n]*\bcanImport\s*\(\s*NeoBili(?:Domain|Core|Data)\s*\)")
HARNESS_SOURCE = re.compile(r'"\$(?:\{(?P<braced>APP|HARNESS|ROOT)\}|(?P<plain>APP|HARNESS|ROOT))/(?P<path>[^"\n]+\.swift)"')


def source(path):
    # Strip documentation before scanning symbols. Strings are retained because
    # type names inside interpolation may represent actual dependencies.
    text = re.sub(r"/\*.*?\*/", lambda match: "\n" * match[0].count("\n"), path.read_text(), flags=re.S)
    return re.sub(r"(?m)^[ \t]*//.*$", "", text)


def declared_types(text):
    # The file-level scan excludes indented local types and private declarations.
    for match in TYPE_DECLARATION.finditer(text):
        modifiers = re.sub(ATTRIBUTE, "", match["modifiers"]).split()
        if "private" not in modifiers:
            yield match["name"]


def check_harness_sources(root):
    errors = []
    harness = root / "offline-harness"
    bases = {"ROOT": root, "APP": root / "NeoBili", "HARNESS": harness}
    manifest = harness / "sources.sh"
    if not manifest.is_file():
        return ["offline-harness/sources.sh: missing source manifest"]
    for script in sorted(harness.glob("*.sh")):
        for number, line in enumerate(script.read_text().splitlines(), 1):
            if line.lstrip().startswith("#"):
                continue
            for match in HARNESS_SOURCE.finditer(line):
                path = bases[match["braced"] or match["plain"]] / match["path"]
                if not path.is_file():
                    errors.append(f"{script.relative_to(root)}:{number}: missing Swift source {match[0]}")
    return errors


def check_architecture(root):
    app = root / "NeoBili"
    files = {path: source(path) for path in sorted(app.rglob("*.swift"))}
    symbols = {}
    for path, text in files.items():
        for name in declared_types(text):
            symbols.setdefault(name, set()).add(path.relative_to(app).parts[0])
    errors = check_harness_sources(root)
    test_sources = {path: source(path) for path in sorted((root / "NeoBiliTests").rglob("*.swift"))}
    harness_sources = {path: source(path) for path in sorted((root / "offline-harness/src").rglob("*.swift"))}
    for path, swift_source in (files | test_sources | harness_sources).items():
        for number, line in enumerate(swift_source.splitlines(), 1):
            if PROJECT_IMPORT_GUARD.search(line):
                errors.append(f"{path.relative_to(root)}:{number}: import NeoBili modules directly")
    for path, text in files.items():
        parts = path.relative_to(app).parts
        layer = parts[0]
        scope = "Core/UI" if parts[:2] == ("Core", "UI") else layer
        banned = FORBIDDEN.get(scope, set())
        imported_modules = set(MODULE_IMPORT.findall(text))
        pure_core = layer == "Core" and parts[1] in {"Caching", "Formatting"}
        allowed_modules = None
        if layer == "Domain" or pure_core:
            allowed_modules = set()
        elif scope in {"Data", "Features", "Application", "Core/UI"}:
            allowed_modules = {"NeoBiliDomain", "NeoBiliCore"}
        if allowed_modules is not None:
            for module in sorted(imported_modules - allowed_modules):
                errors.append(f"{path.relative_to(root)}: {module} is not an allowed module dependency")
        for name in sorted(set(re.findall(r"\b\w+\b", text))):
            if symbols.get(name, set()) & banned:
                errors.append(f"{path.relative_to(root)}: {name} crosses the {scope} boundary")
        if layer in {"Features", "Application", "Domain"} and re.search(r"\b(?:URLSession|URLRequest|APIClient|DeviceIdentity)\b", text):
            errors.append(f"{path.relative_to(root)}: transport/identity belongs in Data or Platform")
        # Service operations describe I/O the Application layer awaits; pinning them
        # to MainActor would put signing, decoding and parsing back on the UI thread.
        if layer == "Domain" and path.parent.name == "Services":
            for number, line in enumerate(text.splitlines(), 1):
                if re.search(r"\b\w+Operation\b\s*:", line) and "@MainActor" in line:
                    errors.append(f"{path.relative_to(root)}:{number}: service operations must stay nonisolated")
        if layer == "Domain" and re.search(r"import (?:SwiftUI|UIKit|WebKit|MPVKit)\b", text):
            errors.append(f"{path.relative_to(root)}: domain values must not import UI frameworks")
    return errors, len(files)


def main():
    errors, file_count = check_architecture(ROOT)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Architecture boundaries and offline sources passed ({file_count} Swift files).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
