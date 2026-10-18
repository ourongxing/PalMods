"""Package the Lua development build; never deploy or publish."""
from pathlib import Path
import json
from zipfile import ZipFile, ZIP_DEFLATED
from schema_config import patches
MOD = Path(__file__).resolve().parents[1]
output = MOD.parents[1] / 'dist/BetterArena/BetterArena-0.1.0.zip'
output.parent.mkdir(parents=True, exist_ok=True)
base = json.loads((MOD / 'mod/Config/arena_rewards.base.json').read_text(encoding='utf-8'))
rewards, points = patches(base, 2)
with ZipFile(output, 'w', ZIP_DEFLATED) as archive:
    for path in sorted((MOD / 'mod').rglob('*')):
        if path.is_file():
            archive.write(path, 'BetterArena/' + path.relative_to(MOD / 'mod').as_posix())
    archive.write(MOD / 'README.md', 'BetterArena/README.md')
    archive.writestr('PalSchema/mods/BetterArena/raw/arena_rewards.json', json.dumps(rewards, indent=2) + '\n')
    archive.writestr('PalSchema/mods/BetterArena/blueprints/arena_points.json', json.dumps(points, indent=2) + '\n')
print(output)
