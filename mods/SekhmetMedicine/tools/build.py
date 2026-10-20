"""Package the single-field PalSchema patch without deployment."""
from pathlib import Path
import json
import shutil
from zipfile import ZipFile, ZIP_DEFLATED

MOD = Path(__file__).resolve().parents[1]
ROOT = MOD.parents[1]

def main():
    source = MOD / 'mod/raw/sekhmet_medicine.json'
    patch = json.loads(source.read_text(encoding='utf-8'))
    assert patch == {'DT_PalMonsterParameter_Common': {
        'BOSS_Sekhmet': {'WorkSuitability_ProductMedicine': 3}}}
    output = ROOT / 'dist/SekhmetMedicine'
    stage = output / 'SekhmetMedicine'
    (stage / 'raw').mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, stage / 'raw' / source.name)
    shutil.copy2(MOD / 'README.md', stage / 'README.md')
    archive = output / 'SekhmetMedicine-0.1.0.zip'
    with ZipFile(archive, 'w', ZIP_DEFLATED) as package:
        for path in sorted(stage.rglob('*')):
            if path.is_file():
                package.write(path, 'Mods/NativeMods/UE4SS/Mods/PalSchema/mods/SekhmetMedicine/' + path.relative_to(stage).as_posix())
    print(archive)

if __name__ == '__main__':
    main()
