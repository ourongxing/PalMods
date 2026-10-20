"""Package the time-only PalSchema patch; never install."""
from pathlib import Path
import argparse
import shutil
import subprocess
import sys
from zipfile import ZipFile, ZIP_DEFLATED

MOD = Path(__file__).resolve().parents[1]
ROOT = MOD.parents[1]

def main():
    argparse.ArgumentParser(description=__doc__).parse_args()
    subprocess.run([sys.executable, str(MOD / 'tests/run.py')], check=True)
    output = ROOT / 'dist/BetterExpedition'
    stage = output / 'BetterExpedition'
    if stage.exists():
        assert stage.resolve().is_relative_to((ROOT / 'dist').resolve())
        shutil.rmtree(stage)
    shutil.copytree(MOD / 'mod', stage)
    shutil.copy2(MOD / 'README.md', stage / 'README.md')
    archive = output / 'BetterExpedition-0.1.0.zip'
    with ZipFile(archive, 'w', ZIP_DEFLATED) as package:
        for path in sorted(stage.rglob('*')):
            if path.is_file():
                package.write(path, 'Mods/NativeMods/UE4SS/Mods/PalSchema/mods/BetterExpedition/' + path.relative_to(stage).as_posix())
    print(archive)

if __name__ == '__main__':
    main()
