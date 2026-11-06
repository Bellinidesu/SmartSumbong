"""Inter Tight, cut into the static files the portal and the app ship (5 Nov 2026).

Google Fonts publishes Inter Tight (and Inter) as variable fonts. The portal loads static woff2 files (Latin subset, the same
cut as the Inter files beside them) and the app bundles static TTFs, so this makes both from the published sources:

    python tools/make_inter_tight.py INTER_TIGHT.ttf [--italic INTER_TIGHT_ITALIC.ttf] [--inter-italic INTER_ITALIC.ttf]

INTER_TIGHT is `InterTight[wght].ttf` from github.com/google/fonts, ofl/intertight; the italic ones are beside it
(`InterTight-Italic[wght].ttf`) and in ofl/inter (`Inter-Italic[opsz,wght].ttf`). The commits are in
admin/assets/vendor/vendor.json. Needs fonttools and brotli (pip install fonttools brotli).

    admin/assets/vendor/fonts/inter-tight-{regular,medium,semibold,bold}.woff2        the portal (Latin subset)
    mobile/resident/assets/fonts/InterTight-{Regular,Medium,SemiBold,Bold}.ttf        the app (Latin and symbols)
    mobile/resident/assets/fonts/InterTight-{Italic,MediumItalic,BoldItalic}.ttf      the app's italics
    mobile/resident/assets/fonts/Inter-{Italic,MediumItalic}.ttf                      Inter's italics (hints), at opsz 14

The heaviest weight in the system is Bold: an 800 asks for the Bold file (fonts.css, pubspec.yaml), as Apple's headings do.
"""
import os, sys
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools import subset

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB = os.path.join(ROOT, 'admin', 'assets', 'vendor', 'fonts')
APP = os.path.join(ROOT, 'mobile', 'resident', 'assets', 'fonts')
WEIGHTS = {400: ('regular', 'Regular'), 500: ('medium', 'Medium'), 600: ('semibold', 'SemiBold'), 700: ('bold', 'Bold')}
ITALICS = {400: 'Italic', 500: 'MediumItalic', 700: 'BoldItalic'}
# Google's own "latin" subset, so the portal's files match what the Inter files beside them cover
LATIN = ('U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,U+0308,U+0329,U+2000-206F,U+20AC,U+2122,'
         'U+2191,U+2193,U+2212,U+2215,U+FEFF,U+FFFD')
# the app's: Latin with its extensions (Filipino names carry accents), punctuation, currency (the peso), arrows, maths, shapes
APP_SET = ('U+0000-024F,U+0259,U+02BB-02BC,U+02C6-02DC,U+0300-0304,U+0308,U+0329,U+1E00-1EFF,U+2000-206F,U+20A0-20CF,U+2100-218F,'
           'U+2190-21FF,U+2200-22FF,U+25A0-25FF,U+2713-2714,U+FEFF,U+FFFD')


def instance(path, axes):
    try:
        return instancer.instantiateVariableFont(TTFont(path), axes, updateFontNames=True)
    except Exception:
        return instancer.instantiateVariableFont(TTFont(path), axes)


def cut(font, unicodes, flavor=None):
    opts = subset.Options(); opts.layout_features = ['*']; opts.name_IDs = ['*']; opts.notdef_outline = True
    if flavor: opts.flavor = flavor
    s = subset.Subsetter(opts); s.populate(unicodes=subset.parse_unicodes(unicodes)); s.subset(font)
    font.flavor = flavor
    return font


def main():
    args = sys.argv[1:]
    src = args[0]
    italic = args[args.index('--italic') + 1] if '--italic' in args else None
    inter_italic = args[args.index('--inter-italic') + 1] if '--inter-italic' in args else None
    os.makedirs(WEB, exist_ok=True); os.makedirs(APP, exist_ok=True)
    for w, (web, app) in WEIGHTS.items():
        cut(instance(src, {'wght': w}), APP_SET).save(os.path.join(APP, f'InterTight-{app}.ttf'))
        cut(instance(src, {'wght': w}), LATIN, 'woff2').save(os.path.join(WEB, f'inter-tight-{web}.woff2'))
        print('Inter Tight', w)
    if italic:
        for w, name in ITALICS.items():
            cut(instance(italic, {'wght': w}), APP_SET).save(os.path.join(APP, f'InterTight-{name}.ttf')); print('Inter Tight italic', w)
    if inter_italic:
        for w, name in {400: 'Italic', 500: 'MediumItalic'}.items():
            cut(instance(inter_italic, {'opsz': 14, 'wght': w}), APP_SET).save(os.path.join(APP, f'Inter-{name}.ttf')); print('Inter italic', w)


if __name__ == '__main__':
    main()
