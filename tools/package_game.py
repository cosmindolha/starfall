#!/usr/bin/env python3
"""Ship only runtime source/assets, with a deterministic ZIP manifest."""
import hashlib
import json
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'dist'
OUT.mkdir(exist_ok=True)
files = [ROOT/'main.lua', ROOT/'conf.lua', ROOT/'ASSETS.md']
files += sorted((ROOT/'game').glob('*.lua'))
files += sorted(p for p in (ROOT/'assets').rglob('*')
                if p.is_file() and not p.is_symlink()
                and not any(part.startswith('.') for part in p.relative_to(ROOT).parts)
                and p.suffix.lower() in {'.png', '.ogg', '.wav', '.ttf', '.txt', '.lua'})
manifest = []
with zipfile.ZipFile(OUT/'starfall.love', 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as bundle:
    for path in files:
        data = path.read_bytes()
        name = str(path.relative_to(ROOT))
        item = zipfile.ZipInfo(name, (2026, 9, 30, 12, 0, 0))
        item.compress_type = zipfile.ZIP_DEFLATED
        bundle.writestr(item, data)
        manifest.append(dict(path=name, bytes=len(data), sha256=hashlib.sha256(data).hexdigest()))
(OUT/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
print(OUT/'starfall.love')
print('Runtime files:', len(files), 'bytes:', (OUT/'starfall.love').stat().st_size)
