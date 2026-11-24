#!/usr/bin/env python3
"""Converts the launcher's WOFF2 fonts to TrueType for the native loading screen (App/LoadingView.swift).

UIKit cannot load WOFF2. Tektur and Share Tech Mono are under the SIL Open Font License (Launcher/media/fonts).
The TrueType copies go to GeneratedResources (bundled at the app's root as MCTektur.ttf, MCShareTechMono.ttf).
fontTools and brotli are installed into Build/pydeps when missing. Never fatal: without the fonts the loading
screen uses system fonts.
"""
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = root / 'Launcher/media/fonts'
out = root / 'GeneratedResources'
fonts = {'tektur-latin-900-normal.woff2': 'MCTektur.ttf', 'share-tech-mono-latin-400-normal.woff2': 'MCShareTechMono.ttf'}


def main():
    if all((out / name).is_file() for name in fonts.values()):
        print('Loading-screen fonts present.')
        return
    try:
        from fontTools.ttLib import TTFont
        import brotli  # noqa: F401  (WOFF2 decoding)
    except ImportError:
        deps = root / 'Build/pydeps'
        subprocess.run([sys.executable, '-m', 'pip', 'install', '--quiet', '--disable-pip-version-check', '--target', str(deps),
                        'fonttools', 'brotli'], check=True)
        sys.path.insert(0, str(deps))
        from fontTools.ttLib import TTFont
    out.mkdir(parents=True, exist_ok=True)
    for woff2, ttf in fonts.items():
        font = TTFont(str(source / woff2))
        font.flavor = None
        font.save(str(out / ttf))
        print('Loading-screen font:', ttf)


try:
    main()
except Exception as error:  # the app falls back to system fonts
    print('Loading-screen fonts skipped:', error)
