#!/usr/bin/env python3
"""Build editable SVG artwork and native Icon Composer files from AppTheme."""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
THEMES = re.findall(
    r'\.init\(id: "([^"]+)", name: (?:String\(localized: )?"([^"]+)"\)?, hex: 0x([0-9A-F]+)\)',
    (ROOT / 'NeoBili/Core/UI/AppTheme.swift').read_text(),
)
# Block "N" monogram after PiliPala's extruded "P": a white face with a thin
# theme-colored rim, extruded 125 units toward the lower left. EXTRUSION is the
# exact sweep of the rimmed face; FACE is cut out of it to show the background.
EXTRUSION = ('M 250 778 L 378 778 L 432 725 L 453 778 L 648 778 L 774 654 '
             'L 774 246 L 646 246 L 592 299 L 571 246 L 376 246 L 250 370 Z')
FACE = ('M 390 260 L 562 260 L 660 512 L 660 260 L 760 260 L 760 640 '
        'L 588 640 L 490 388 L 490 640 L 390 640 Z')
MARK = f'<path d="{EXTRUSION} {FACE}" fill-rule="evenodd"'

for theme_id, name, theme_hex in THEMES:
    icon_name = 'NeoBiliIcon' if theme_id == 'pink' else f'NeoBiliIcon-{theme_id}'
    destination = ROOT / 'NeoBili/Resources/AppIcons' / f'{icon_name}.icon'
    assets = destination / 'Assets'
    assets.mkdir(parents=True, exist_ok=True)
    for stale in ('Play.svg', 'Backing.svg'):
        (assets / stale).unlink(missing_ok=True)
    (assets / 'Mark.svg').write_text(
        '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
        f'viewBox="0 0 1024 1024">{MARK} fill="#{theme_hex}"/></svg>\n'
    )
    document = {
        'fill': {'solid': 'srgb:1.00000,1.00000,1.00000,1.00000'},
        'groups': [{
            'layers': [
                {'image-name': 'Mark.svg', 'name': 'N mark'},
            ],
        }],
        'supported-platforms': {'squares': 'shared'},
    }
    # Preserve material settings edited in Icon Composer.
    document_path = destination / 'icon.json'
    if document_path.exists():
        document = json.loads(document_path.read_text())
        document['fill'] = {'solid': 'srgb:1.00000,1.00000,1.00000,1.00000'}
        layer = next((l for l in document['groups'][0]['layers']
                      if l.get('image-name') in ('Play.svg', 'Mark.svg')), {})
        layer.update({'image-name': 'Mark.svg', 'name': 'N mark'})
        document['groups'][0]['layers'] = [layer]
    document_path.write_text(json.dumps(document, indent=2) + '\n')
    if theme_id == 'pink':
        # Editable flat master, viewable in professional vector drawing tools.
        master = ROOT / 'design/app-icon-2026/NMark-white-master.svg'
        master.write_text(
            '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
            'viewBox="0 0 1024 1024">\n'
            '<rect width="1024" height="1024" fill="#FFFFFF"/>\n'
            f'{MARK} id="mark" fill="#{theme_hex}"/>\n'
            '</svg>\n'
        )
print(f'Created {len(THEMES)} white-background vector icons')
