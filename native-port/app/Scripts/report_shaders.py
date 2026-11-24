#!/usr/bin/env python3
"""Reports the game's shader index: how many shaders the app's Metal library leaves out, and what the
shaders the renderer found missing on a phone are (Tests/missing_shaders.txt: '<hash> <stage>' from
'Metal renderer: no precompiled shader' log lines). Diagnostic only; never fails the build.

Usage: report_shaders.py <shaders folder with index.json> [missing list]
"""
import collections
import json
import sys
from pathlib import Path


def main():
    folder = Path(sys.argv[1])
    missing = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(__file__).resolve().parents[1] / 'Tests/missing_shaders.txt'
    index = json.loads((folder / 'index.json').read_text())
    records = {h: r for h, r in index.items() if not h.startswith('_')}
    built = [h for h, r in records.items() if r.get('ok') and r.get('stage') in ('vs', 'ps', 'cs')]
    left = collections.Counter((r.get('stage'), bool(r.get('ok'))) for h, r in records.items() if h not in set(built))
    print(f'Shader index: {len(records)} shaders, {len(built)} in the Metal library; left out by (stage, ok): {dict(left)}')
    keys = sorted({k for r in records.values() for k in r})
    print('Index fields:', ', '.join(keys))
    if not missing.exists():
        return
    lowered = {h.lower(): h for h in records}
    for line in missing.read_text().split('\n'):
        if not line.strip():
            continue
        h = line.split()[0].lower()
        key = lowered.get(h)
        if key is None:
            # The renderer prints the 64-bit hash as two 32-bit halves; try the halves swapped too.
            swapped = h[8:] + h[:8]
            key = lowered.get(swapped)
        if key is None:
            print(f'  {h}: not in the index')
            continue
        r = records[key]
        detail = {k: v for k, v in r.items() if k not in ('p',)}
        print(f'  {h}: {json.dumps(detail)[:400]}')


try:
    main()
except Exception as error:
    print('Shader report skipped:', error)
