"""Package the native-UI Lua mod without changing game files."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

MOD = Path(__file__).resolve().parents[1]
ROOT = MOD.parents[1]
output = ROOT / 'dist/BetterPalSouls/BetterPalSouls-1.0.0.zip'
output.parent.mkdir(parents=True, exist_ok=True)
with ZipFile(output, 'w', ZIP_DEFLATED) as archive:
    for path in sorted((MOD / 'mod').rglob('*')):
        if path.is_file():
            archive.write(path, 'Mods/NativeMods/UE4SS/Mods/BetterPalSouls/' + path.relative_to(MOD / 'mod').as_posix())
    archive.write(MOD / 'README.md', 'BetterPalSouls-README.md')
print(output)
