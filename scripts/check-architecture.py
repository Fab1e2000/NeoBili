#!/usr/bin/env python3
"""Check source-layer dependencies without importing or executing application code."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "NeoBili"
FORBIDDEN = {
    "Domain": {"Features", "Application", "Data", "Core", "Platform"},
    "Data": {"Features", "Application"},
    "Features": {"Data"},
    "Application": {"Data"},
}


def source(path):
    # Strip documentation before scanning symbols. Strings are retained because
    # type names inside interpolation may represent actual dependencies.
    text = re.sub(r"/\*.*?\*/", "", path.read_text(), flags=re.S)
    return re.sub(r"(?m)^\s*//.*$", "", text)


def main():
    files = sorted(APP.rglob("*.swift"))
    symbols = {}
    for path in files:
        for name in re.findall(r"^(?:final |private |public |@MainActor )*(?:struct|class|actor|enum|protocol) (\w+)", source(path), re.M):
            symbols.setdefault(name, set()).add(path.relative_to(APP).parts[0])
    errors = []
    for path in files:
        layer = path.relative_to(APP).parts[0]
        text = source(path)
        banned = FORBIDDEN.get(layer, set())
        for name in sorted(set(re.findall(r"\b\w+\b", text))):
            if symbols.get(name, set()) & banned:
                errors.append(f"{path.relative_to(ROOT)}: {name} crosses the {layer} boundary")
        if layer in {"Features", "Application", "Domain"} and re.search(r"\b(?:URLSession|URLRequest|APIClient|DeviceIdentity)\b", text):
            errors.append(f"{path.relative_to(ROOT)}: transport/identity belongs in Data or Platform")
        if layer == "Domain" and re.search(r"import (?:SwiftUI|UIKit|WebKit|MPVKit)\b", text):
            errors.append(f"{path.relative_to(ROOT)}: domain values must not import UI frameworks")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Architecture boundaries passed ({len(files)} Swift files). This source check supplements compilation; it is not a Swift module boundary.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
