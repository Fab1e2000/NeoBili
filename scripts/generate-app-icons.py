#!/usr/bin/env python3
"""Build editable SVG artwork and native Icon Composer files from AppTheme."""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
THEMES = re.findall(
    r'\.init\(id: "([^"]+)", name: "([^"]+)", hex: 0x([0-9A-F]+)\)',
    (ROOT / 'NeoBili/Core/UI/AppTheme.swift').read_text(),
)
# Rounded, optically centered play symbol. No baked material or lighting effects.
SHAPE = ('M 373 187 C 327 161 278 185 278 243 L 278 781 '
         'C 278 839 327 863 373 837 L 828 576 '
         'C 886 543 886 481 828 448 Z')

# Keep the full 1024 canvas; only scale foreground artwork, never the icon mask.
FOREGROUND = 'translate(484 499) scale(0.80) translate(-512 -512)'

for theme_id, name, theme_hex in THEMES:
    icon_name = 'NeoBiliIcon' if theme_id == 'pink' else f'NeoBiliIcon-{theme_id}'
    destination = ROOT / 'NeoBili/Resources/AppIcons' / f'{icon_name}.icon'
    assets = destination / 'Assets'
    assets.mkdir(parents=True, exist_ok=True)
    channels = [int(theme_hex[i:i + 2], 16) for i in (0, 2, 4)]
    backing_hex = ''.join(f'{round(c * 0.40 + 255 * 0.60):02X}' for c in channels)
    layers = [('Play.svg', f'#{theme_hex}', FOREGROUND),
              ('Backing.svg', f'#{backing_hex}', FOREGROUND + ' translate(-48 38)')]
    for filename, fill, transform in layers:
        (assets / filename).write_text(
            '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
            f'viewBox="0 0 1024 1024"><path d="{SHAPE}" fill="{fill}" '
            f'transform="{transform}"/></svg>\n'
        )
    document = {
        'fill': {'solid': 'srgb:1.00000,1.00000,1.00000,1.00000'},
        'groups': [{
            'layers': [
                {'image-name': 'Play.svg', 'name': 'Theme play'},
                {'image-name': 'Backing.svg', 'name': 'Offset play'},
            ],
        }],
        'supported-platforms': {'squares': 'shared'},
    }
    # Preserve material settings edited in Icon Composer.
    document_path = destination / 'icon.json'
    if document_path.exists():
        document = json.loads(document_path.read_text())
        document['fill'] = {'solid': 'srgb:1.00000,1.00000,1.00000,1.00000'}
    document_path.write_text(json.dumps(document, indent=2) + '\n')
    if theme_id == 'pink':
        # Editable flat master, viewable in professional vector drawing tools.
        master = ROOT / 'design/app-icon-2026/LayeredPlay-white-master.svg'
        master.write_text(
            '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
            'viewBox="0 0 1024 1024">\n'
            '<rect width="1024" height="1024" fill="#FFFFFF"/>\n'
            f'<path id="backing" d="{SHAPE}" fill="#{backing_hex}" transform="{FOREGROUND} translate(-48 38)"/>\n'
            f'<path id="play" d="{SHAPE}" fill="#{theme_hex}" transform="{FOREGROUND}"/>\n'
            '</svg>\n'
        )
print(f'Created {len(THEMES)} white-background vector icons')
