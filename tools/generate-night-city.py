#!/usr/bin/env python3
"""Render the original, deterministic Night Circuit wallpaper as SVG.

Usage: python3 tools/generate-night-city.py /tmp/night-circuit.svg
       rsvg-convert -o dotfiles/.local/share/wallpapers/night-circuit.png /tmp/night-circuit.svg
No network, fonts, third-party Python packages, or SVG filters are needed.
"""
import random
import sys
from pathlib import Path


def generate() -> str:
    rng = random.Random(2077)
    out = ['''<svg xmlns="http://www.w3.org/2000/svg" width="3840" height="2160" viewBox="0 0 3840 2160">
<defs>
 <linearGradient id="sky" x2="0" y2="1"><stop stop-color="#040711"/><stop offset=".58" stop-color="#101429"/><stop offset="1" stop-color="#25132f"/></linearGradient>
 <radialGradient id="haze"><stop stop-color="#592b73" stop-opacity=".68"/><stop offset="1" stop-color="#121328" stop-opacity="0"/></radialGradient>
 <linearGradient id="sun" gradientUnits="userSpaceOnUse" x1="0" y1="505" x2="0" y2="1215"><stop stop-color="#ff91ce"/><stop offset=".45" stop-color="#dc48bc"/><stop offset="1" stop-color="#514bd0"/></linearGradient>
 <linearGradient id="street" x2="0" y2="1"><stop stop-color="#111a30"/><stop offset="1" stop-color="#030812"/></linearGradient>
 <linearGradient id="cyan" x2="0" y2="1"><stop stop-color="#43e7f3"/><stop offset="1" stop-color="#14749a" stop-opacity="0"/></linearGradient>
 <linearGradient id="pink" x2="0" y2="1"><stop stop-color="#f376d1"/><stop offset="1" stop-color="#713b8d" stop-opacity="0"/></linearGradient>
 <clipPath id="disc"><circle cx="2420" cy="860" r="355"/></clipPath>
</defs>
<path fill="url(#sky)" d="M0 0H3840V2160H0z"/>
<ellipse cx="2430" cy="1040" rx="1550" ry="1050" fill="url(#haze)"/>
''']
    # Sparse stars and tiny distant aircraft, not a noisy field behind desktop icons.
    for _ in range(95):
        x, y = rng.randrange(100, 3740), rng.randrange(100, 990)
        out.append(f'<circle cx="{x}" cy="{y}" r="{rng.choice([1, 1, 1.5])}" fill="#95c1db" opacity="{rng.uniform(.12, .46):.2f}"/>')
    out.append('<circle cx="2420" cy="860" r="370" fill="none" stroke="#ba65d0" stroke-opacity=".2" stroke-width="1"/>')
    out.append('<g clip-path="url(#disc)" fill="url(#sun)">')
    out.append('<path d="M2050 500H2790V850H2050z"/>')
    for y in range(864, 1220, 24):
        height = max(3, 19 - (y - 864) // 28)
        out.append(f'<path d="M2050 {y}H2790v{height}H2050z"/>')
    out.append('</g>')
    # Three architectural depths. Window grids use a fixed seed, with unlit floors.
    for layer, (base, minimum, maximum, fill, window, density) in enumerate([
        (1390, 130, 440, '#19203a', '#59618b', .28),
        (1510, 220, 680, '#0d1529', '#527995', .22),
        (1650, 280, 850, '#080f20', '#6ebac9', .16),
    ]):
        x = -90
        while x < 3900:
            width = rng.randrange(75, 185)
            height = rng.randrange(minimum, maximum)
            top = base - height
            out.append(f'<path d="M{x} {base}V{top}h{width}V{base}z" fill="{fill}"/>')
            if rng.random() < .45:
                cap = rng.randrange(12, 38)
                out.append(f'<path d="M{x+width//3} {top}v-{cap}h{width//3}v{cap}" fill="{fill}"/>')
            if layer > 0 and rng.random() < .35:
                color = '#52cddb' if rng.random() < .65 else '#c760bf'
                out.append(f'<path d="M{x+2} {base-15}V{top+2}h{width-4}" fill="none" stroke="{color}" stroke-opacity=".45" stroke-width="2"/>')
            for wy in range(top + 20, base - 12, 21):
                for wx in range(x + 12, x + width - 8, 15):
                    if rng.random() < density:
                        color = rng.choice([window, window, '#aa709b', '#cba77b'])
                        out.append(f'<path d="M{wx} {wy}h4v7h-4z" fill="{color}" opacity="{rng.uniform(.25,.7):.2f}"/>')
            if layer == 2 and height > 520 and rng.random() < .6:
                color = rng.choice(['#60dce4', '#bd66cd'])
                sign_y = top + rng.randrange(70, 150)
                out.append(f'<path d="M{x+width-16} {sign_y}h10v115h-10z" fill="{color}" opacity=".75"/>')
                for sy in range(sign_y + 7, sign_y + 105, 18):
                    out.append(f'<path d="M{x+width-15} {sy}h8v3h-8z" fill="#101529"/>')
            x += width + rng.randrange(5, 30)
    # Signature antenna/spire, with a purposeful silhouette rather than text logos.
    out.append('''<path d="M2860 1580V680l24-56V430h4v194l24 56v900z" fill="#080f20"/>
<path d="M2861 1500V690l23-55V470" stroke="#52deed" stroke-width="3" fill="none" opacity=".7"/>
<path d="M2910 740v610" stroke="#e674cd" stroke-width="2" opacity=".55"/>
<path d="M0 1590Q1900 1460 3840 1590V2160H0z" fill="url(#street)"/>
<path d="M1740 1570L920 2160H3110L2330 1570z" fill="#0b1324"/>
<path d="M1740 1570L920 2160M2330 1570L3110 2160" stroke="#253449" stroke-width="3" fill="none"/>
<path d="M1770 1570L1030 2160" stroke="url(#cyan)" stroke-width="5"/>
<path d="M2300 1570L3000 2160" stroke="url(#pink)" stroke-width="4"/>
''')
    # Broken reflections on wet pavement, growing toward the foreground.
    for _ in range(300):
        y = rng.randrange(1580, 2160)
        depth = (y - 1570) / 590
        x = int(2040 + rng.uniform(-1, 1) * (230 + depth * 1250))
        length = rng.randrange(5, max(7, int(20 + depth * 120)))
        color = rng.choice(['#36d2e2', '#3c708c', '#bf59bd', '#6861ad'])
        out.append(f'<path d="M{x} {y}h{length}" stroke="{color}" stroke-width="{rng.choice([1, 1, 2])}" opacity="{rng.uniform(.05,.24):.2f}"/>')
    # Dark foreground framing and minimal transit infrastructure.
    out.append('''<path d="M0 1870l610-90 250 120v260H0zM3840 1810l-420-30-225 150v230h645z" fill="#030812"/>
<path d="M0 1870l610-90 250 120M3840 1810l-420-30-225 150" stroke="#24314a" stroke-width="3" fill="none"/>
<path d="M0 1902l605-87 252 120" stroke="#2995ac" stroke-width="2" fill="none" opacity=".55"/>
<path d="M3220 1945l210-129 410 31" stroke="#a551a5" stroke-width="2" fill="none" opacity=".5"/>
<path d="M450 1800V1400h280M3310 1790v-360h-190" stroke="#060c19" stroke-width="12" fill="none"/>
<path d="M650 1403h80M3120 1433h80" stroke="#74dae8" stroke-width="4"/>
</svg>''')
    return '\n'.join(out)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: generate-night-city.py OUTPUT.svg')
    Path(sys.argv[1]).write_text(generate(), encoding='utf-8')
