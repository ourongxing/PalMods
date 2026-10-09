"""Package the Lua mod without installing it."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

MOD = Path(__file__).resolve().parents[1]
ROOT = MOD.parents[1]
output = ROOT / 'dist/AnywherePalBox/AnywherePalBox-1.0.0.zip'
output.parent.mkdir(parents=True, exist_ok=True)
with ZipFile(output, 'w', ZIP_DEFLATED) as archive:
    for path in sorted((MOD / 'mod').rglob('*')):
        if path.is_file():
            archive.write(path, 'AnywherePalBox/' + path.relative_to(MOD / 'mod').as_posix())
    archive.write(MOD / 'README.md', 'AnywherePalBox/README.md')
print(output)
