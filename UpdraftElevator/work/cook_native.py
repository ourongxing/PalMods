from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from palmods import use_mod_directory
use_mod_directory('UpdraftElevator')
import subprocess
from palmods import UNREAL_EDITOR
root=Path('work/WindNative').resolve()
assets=sorted((root/'Content/Mods/CodexWindNative').rglob('*.uasset'))
assert len(assets)==12, f'Expected 3 blueprints, 3 materials, 6 textures; found {len(assets)}'
packages=['/Game/'+p.relative_to(root/'Content').with_suffix('').as_posix() for p in assets]
log=Path('work/native-cook-variants.log').resolve()
args=[str(UNREAL_EDITOR),str(root/'Pal.uproject'),
      '-run=Cook','-TargetPlatform=Windows','-Package='+'+'.join(packages),'-CookSinglePackageNoRefs',
      '-unattended','-NullRHI','-nosplash','-nop4','-SkipEditorContent','-abslog='+str(log)]
with Path('work/native-cook-variants-console.log').open('w') as out:
    result=subprocess.run(args,stdout=out,stderr=subprocess.STDOUT)
for line in log.read_text(encoding='utf-8-sig',errors='replace').splitlines():
    if 'Error:' in line or 'Success -' in line or 'No files found' in line: print(line)
raise SystemExit(result.returncode)
