from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from palmods import use_mod_directory
use_mod_directory('UpdraftElevator')
from datetime import datetime
import subprocess, shutil
from palmods import UNREAL_EDITOR
root=Path('work/WindNative').resolve()
backup=Path('work/native-assets-'+datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
backup.mkdir()
assets=list((root/'Content/Mods/CodexWindNative').rglob('*.uasset'))
assets.append(root/'Content/Pal/Effect/Common/JumpSpot/NS_JumpSpot.uasset')
for p in assets:
    if p.exists():
        dest=backup/p.relative_to(root/'Content')
        dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.move(str(p),str(dest))
log=Path('work/native-build-test.log').resolve()
with Path('work/native-build-test-console.log').open('w') as out:
    result=subprocess.run([str(UNREAL_EDITOR),str(root/'Pal.uproject'),'-run=WindBuild','-unattended','-NullRHI','-nosplash','-nop4','-abslog='+str(log)],stdout=out,stderr=subprocess.STDOUT)
for line in log.read_text(encoding='utf-8-sig',errors='replace').splitlines():
    if any(x in line for x in ['WIND_','error code:','Fatal error:']): print(line)
print('Editor exit:',result.returncode)
raise SystemExit(result.returncode)
