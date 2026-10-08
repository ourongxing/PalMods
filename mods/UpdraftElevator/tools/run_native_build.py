from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from palmods import use_mod_directory, build_directory
use_mod_directory('UpdraftElevator')
build_directory('UpdraftElevator')
from datetime import datetime
import subprocess, shutil
from palmods import UNREAL_EDITOR
root=Path('native').resolve()
backup=Path('../../.build/UpdraftElevator/backups/assets-'+datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
backup.mkdir(parents=True)
assets=list((root/'Content/Mods/CodexWindNative').rglob('*.uasset'))
assets.append(root/'Content/Pal/Effect/Common/JumpSpot/NS_JumpSpot.uasset')
for p in assets:
    if p.exists():
        dest=backup/p.relative_to(root/'Content')
        dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.move(str(p),str(dest))
log=Path('../../.build/UpdraftElevator/build-test.log').resolve()
with Path('../../.build/UpdraftElevator/build-test-console.log').open('w') as out:
    result=subprocess.run([str(UNREAL_EDITOR),str(root/'Pal.uproject'),'-run=WindBuild','-unattended','-NullRHI','-nosplash','-nop4','-abslog='+str(log)],stdout=out,stderr=subprocess.STDOUT)
for line in log.read_text(encoding='utf-8-sig',errors='replace').splitlines():
    if any(x in line for x in ['WIND_','error code:','Fatal error:']): print(line)
print('Editor exit:',result.returncode)
raise SystemExit(result.returncode)
