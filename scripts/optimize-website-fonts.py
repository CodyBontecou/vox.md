#!/usr/bin/env python3
"""Subset bundled variable web fonts: pip install 'fonttools[woff]'.

Sources: geist@1.8.2, published by Vercel, under fonts/LICENSE.txt.
Keep the Latin ranges in sync with geist.css. Full fonts retain other languages.
"""
from pathlib import Path
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

FONT_DIR = Path(__file__).resolve().parent.parent / 'website' / 'fonts'
LATIN = (list(range(0x100)) + list(range(0x2000, 0x2070))
         + list(range(0x2190, 0x2200)) + [0x2212, 0x2605])

for source in sorted(FONT_DIR.glob('*-Variable.woff2')):
    options = subset.Options()
    options.flavor = 'woff2'
    font = TTFont(source, lazy=False)
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(unicodes=LATIN)
    subsetter.subset(font)
    font = instantiateVariableFont(font, {'wght': (400, 600)}, inplace=True)
    subset.save_font(font, str(source.with_name(source.stem + '-latin.woff2')), options)
