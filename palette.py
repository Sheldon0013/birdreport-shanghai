#!/usr/bin/env python3
"""Generate harmonious color palettes from a base color."""
import colorsys
import sys

def hex_to_hsl(hex_str):
    h = hex_str.lstrip('#')
    r, g, b = tuple(int(h[i:i+2], 16) / 255.0 for i in (0, 2, 4))
    return colorsys.rgb_to_hls(r, g, b)

def hsl_to_hex(h, l, s):
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return '#{:02x}{:02x}{:02x}'.format(int(r*255), int(g*255), int(b*255))

def generate_palette(base_hex, style='modern'):
    h, _, s = hex_to_hsl(base_hex)
    palettes = {
        'modern': [
            hsl_to_hex(h, 0.12, s),      # dark bg
            hsl_to_hex(h, 0.25, s),      # muted
            hsl_to_hex(h, 0.45, s),      # primary
            hsl_to_hex(h, 0.60, s),      # accent
            hsl_to_hex(h, 0.80, s),      # light
            hsl_to_hex(h, 0.92, s),      # bg
            hsl_to_hex(h, 0.96, s),      # surface
        ],
        'warm': [
            hsl_to_hex(h, 0.10, 0.3),
            hsl_to_hex(h+0.02, 0.25, 0.4),
            hsl_to_hex(h, 0.40, 0.5),
            hsl_to_hex(h-0.01, 0.60, 0.3),
            hsl_to_hex(h+0.01, 0.80, 0.2),
            hsl_to_hex(h, 0.90, 0.15),
            hsl_to_hex(h, 0.96, 0.1),
        ],
    }
    return palettes.get(style, palettes['modern'])

if __name__ == '__main__':
    color = sys.argv[1] if len(sys.argv) > 1 else '#4a7c59'
    style = sys.argv[2] if len(sys.argv) > 2 else 'modern'
    palette = generate_palette(color, style)
    print(f"/* Palette from {color} ({style}) */")
    for i, c in enumerate(palette):
        print(f"--color-{i}: {c};  /* {c} */")
    print()
    for i, c in enumerate(palette):
        bg = 'white' if i > 3 else c
        fg = 'white' if i <= 3 else '#333'
        print(f"\x1b[48;2;{int(c[1:3],16)};{int(c[3:5],16)};{int(c[5:7],16)}m  {c}  \x1b[0m", end=' ')
    print()
