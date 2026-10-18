"""Package the Lua development build; never deploy or publish."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
MOD = Path(__file__).resolve().parents[1]
output = MOD.parents[1] / 'dist/BetterArena/BetterArena-0.1.0.zip'
output.parent.mkdir(parents=True, exist_ok=True)
with ZipFile(output, 'w', ZIP_DEFLATED) as archive:
    for path in sorted((MOD / 'mod').rglob('*')):
        if path.is_file():
            archive.write(path, 'BetterArena/' + path.relative_to(MOD / 'mod').as_posix())
    archive.write(MOD / 'README.md', 'BetterArena/README.md')
print(output)
