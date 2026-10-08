#!/usr/bin/env python3
"""Validate local Markdown destinations, including links to source files."""
from pathlib import Path
import re
import sys
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]


def main():
    files = sorted(ROOT.glob("*.md")) + sorted((ROOT / "docs").rglob("*.md"))
    errors = []
    for path in files:
        # Examples inside fenced code blocks are not navigable Markdown links.
        text = re.sub(r"```.*?```", "", path.read_text(), flags=re.S)
        for raw in re.findall(r"\]\(([^\s)]+)\)", text):
            if re.match(r"[a-zA-Z][a-zA-Z0-9+.-]*:|/|#", raw):
                continue
            destination, _, fragment = raw.partition("#")
            destination = unquote(destination)
            if not destination:
                continue
            target = (path.parent / destination).resolve()
            if not target.is_relative_to(ROOT):
                continue  # Research evidence may refer to external private files.
            if not target.exists():
                errors.append(f"{path.relative_to(ROOT)}: missing {raw}")
            elif fragment and target.suffix == ".md":
                content = target.read_text()
                headings = re.findall(r"(?m)^#+ (.+)$", content)
                anchors = {re.sub(r"[^\w\-\s]", "", heading.lower()).replace(" ", "-") for heading in headings}
                anchors.update(re.findall(r'<a (?:id|name)="([^"]+)"', content))
                if unquote(fragment) not in anchors:
                    errors.append(f"{path.relative_to(ROOT)}: missing section {raw}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print(f"Local documentation links passed ({len(files)} Markdown files).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
