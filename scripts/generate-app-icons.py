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
# Block "B" monogram after PiliPala's extruded "P": a white face with a thin
# theme-colored rim, extruded 150 units toward the lower left. The bowls are
# semicircles (upper r=133 at 643,343; lower r=139 at 659,527) meeting at the
# waist. EXTRUSION is the exact sweep of the 16-unit rimmed face; FACE is cut
# out of it to show the background, and the COUNTERS, which the extrusion
# covers, are cut out of FACE so they show the theme color.
EXTRUSION = ('M 362 194 L 643 194 A 149 149 0 0 1 770.8 419.6 '
             'A 155 155 0 0 1 768.6 636.6 L 618.6 786.6 A 155 155 0 0 1 509 832 '
             'L 212 832 L 212 344 Z')
FACE = ('M 378 210 L 643 210 A 133 133 0 0 1 750 422 '
        'A 139 139 0 0 1 659 666 L 378 666 Z')
COUNTERS = ('M 498 302 L 617 302 A 43 43 0 0 1 617 388 L 498 388 Z '
            'M 498 476 L 635 476 A 47 47 0 0 1 635 570 L 498 570 Z')
MARK = f'<path d="{EXTRUSION} {FACE} {COUNTERS}" fill-rule="evenodd"'

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
                {'image-name': 'Mark.svg', 'name': 'B mark'},
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
        layer.update({'image-name': 'Mark.svg', 'name': 'B mark'})
        document['groups'][0]['layers'] = [layer]
    document_path.write_text(json.dumps(document, indent=2) + '\n')
    if theme_id == 'pink':
        # Editable flat master, viewable in professional vector drawing tools.
        master = ROOT / 'design/app-icon-2026/BMark-white-master.svg'
        master.write_text(
            '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
            'viewBox="0 0 1024 1024">\n'
            '<rect width="1024" height="1024" fill="#FFFFFF"/>\n'
            f'{MARK} id="mark" fill="#{theme_hex}"/>\n'
            '</svg>\n'
        )
print(f'Created {len(THEMES)} white-background vector icons')
