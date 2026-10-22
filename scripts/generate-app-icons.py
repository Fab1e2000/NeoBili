#!/usr/bin/env python3
"""Build editable SVG artwork and native Icon Composer files from AppTheme."""
from pathlib import Path
import json
import math
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
THEMES = re.findall(
    r'\.init\(id: "([^"]+)", name: (?:String\(localized: )?"([^"]+)"\)?, hex: 0x([0-9A-F]+)\)',
    (ROOT / 'NeoBili/Core/UI/AppTheme.swift').read_text(),
)
# Stacked video cards on white: two translucent theme-colored cards peek above a theme-colored
# front card carrying a white play glyph. Each piece is its own Icon Composer
# group so the system Liquid Glass can separate the layers in depth.
BACK = (307, 195, 410, 307, 82)
MIDDLE = (246, 276, 532, 369, 97)
FRONT = (174, 369, 676, 471, 123)


def card(x, y, w, h, r):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}"/>'


def play_path(cx=522, cy=604, height=154, corner=0.24):
    """A play triangle with quadratic rounded corners, as one filled path."""
    width = height * 0.9
    points = [(cx - width * 0.42, cy - height / 2), (cx + width * 0.58, cy),
              (cx - width * 0.42, cy + height / 2)]
    inset = height * corner / 2
    def toward(a, b):
        length = math.dist(a, b)
        return (a[0] + (b[0] - a[0]) * inset / length, a[1] + (b[1] - a[1]) * inset / length)
    parts = []
    for i, p in enumerate(points):
        before, after = toward(p, points[i - 1]), toward(p, points[(i + 1) % 3])
        parts.append(f'{"M" if i == 0 else "L"} {before[0]:.1f} {before[1]:.1f} '
                     f'Q {p[0]:.1f} {p[1]:.1f} {after[0]:.1f} {after[1]:.1f}')
    return ' '.join(parts) + ' Z'


def svg(body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
            f'viewBox="0 0 1024 1024">{body}</svg>\n')


def layers(theme_hex):
    return {
        'Play.svg': f'<path d="{play_path()}" fill="#FFFFFF"/>',
        'Front.svg': f'<g fill="#{theme_hex}">{card(*FRONT)}</g>',
        'Middle.svg': f'<g fill="#{theme_hex}">{card(*MIDDLE)}</g>',
        'Back.svg': f'<g fill="#{theme_hex}">{card(*BACK)}</g>',
    }


def group(*names, opacity=1.0):
    return {
        'layers': [{'image-name': name, 'name': name.removesuffix('.svg'), 'glass': True,
                    'opacity': opacity} for name in names],
        'shadow': {'kind': 'neutral', 'opacity': 0.5},
        'translucency': {'enabled': False, 'value': 0.3},
    }


for theme_id, name, theme_hex in THEMES:
    icon_name = 'NeoBiliIcon' if theme_id == 'pink' else f'NeoBiliIcon-{theme_id}'
    destination = ROOT / 'NeoBili/Resources/AppIcons' / f'{icon_name}.icon'
    assets = destination / 'Assets'
    shutil.rmtree(assets, ignore_errors=True)
    assets.mkdir(parents=True)
    for file_name, body in layers(theme_hex).items():
        (assets / file_name).write_text(svg(body))
    # Icon Composer lists groups front to back.
    document = {
        'fill': {'solid': 'srgb:1.00000,1.00000,1.00000,1.00000'},
        'groups': [group('Play.svg', 'Front.svg'), group('Middle.svg', opacity=0.55),
                   group('Back.svg', opacity=0.3)],
        'supported-platforms': {'squares': 'shared'},
    }
    (destination / 'icon.json').write_text(json.dumps(document, indent=2) + '\n')
    if theme_id == 'pink':
        # Editable flat master, viewable in professional vector drawing tools.
        master = ROOT / 'design/app-icon-2026/Cards-white-master.svg'
        bodies = layers(theme_hex)
        master.write_text(svg(
            '\n<rect width="1024" height="1024" fill="#FFFFFF"/>\n'
            + ''.join(f'<g id="{key.removesuffix(".svg").lower()}" opacity="{alpha}">{bodies[key]}</g>\n'
                      for key, alpha in (('Back.svg', 0.3), ('Middle.svg', 0.55),
                                         ('Front.svg', 1), ('Play.svg', 1)))))
print(f'Created {len(THEMES)} white-background vector icons')
