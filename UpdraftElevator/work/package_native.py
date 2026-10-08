from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from palmods import use_mod_directory
use_mod_directory('UpdraftElevator')
import json, shutil, subprocess, hashlib
from datetime import datetime

root=Path('work/WindNative').resolve()
cooked=root/'Saved/Cooked/Windows/Pal/Content/Mods/CodexWindNative'
stage=Path('work/native-package').resolve()
pakroot=Path('work/native-pak-input').resolve()
target=pakroot/'Pal/Content/Mods/CodexWindNative'
target.mkdir(parents=True,exist_ok=True)
variants=json.loads(Path('work/wind_variants.json').read_text(encoding='utf-8'))
expected=set()
for v in variants:
    s=v['Suffix']
    expected.update({f'BP_Wind{s}',f'Materials/M_WindDeck{s}',
                     f'Textures/T_WindDeck{s}',f'Textures/T_WindIcon{s}'})
files=[]
for name in sorted(expected):
    asset=cooked/(name+'.uasset'); export=cooked/(name+'.uexp')
    assert asset.is_file() and export.is_file(), f'Missing cooked asset: {name}'
    files.extend([asset,export])
    bulk=cooked/(name+'.ubulk')
    if bulk.is_file(): files.append(bulk)
relpaths={p.relative_to(cooked) for p in files}
for p in target.rglob('*'):
    if p.is_file() and p.relative_to(target) not in relpaths:
        assert p.resolve().is_relative_to(target.resolve())
        p.unlink()
for p in files:
    dest=target/p.relative_to(cooked); dest.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(p,dest)
content=b''.join(p.read_bytes() for p in files)
assert b'/Script/Pal' in content and b'/Script/WindEditor' not in content
assert b'/Game/Pal/Effect/Common/JumpSpot/NS_JumpSpot' in content
for v in variants:
    blueprint=b''.join((cooked/(f"BP_Wind{v['Suffix']}"+ext)).read_bytes() for ext in ['.uasset','.uexp'])
    assert b'SpawnActor' not in blueprint and b'ReceiveTick' not in blueprint
schema=stage/'Mods/PalSchema/mods/UpdraftElevator'
(schema/'buildings').mkdir(parents=True,exist_ok=True)
(schema/'paks').mkdir(exist_ok=True)
pak=schema/'paks/UpdraftElevator_P.pak'
from palmods import REPAK
repak=str(REPAK)
subprocess.run([repak,'pack','--version','V11','--compression','Zlib',str(pakroot),str(pak)],check=True)
listing=subprocess.check_output([repak,'list',str(pak)],text=True)
entries=set(listing.strip().splitlines())
assert entries=={'Pal/Content/Mods/CodexWindNative/'+p.as_posix() for p in relpaths}
legacy_stage=stage/'Mods/PalSchema/mods/WindBuildMenu'
if legacy_stage.exists():
    assert legacy_stage.resolve().is_relative_to(stage.resolve())
    shutil.rmtree(legacy_stage)
from wind_data import build_rows
rows=build_rows()
(schema/'buildings/wind_small.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf-8')
subprocess.run([sys.executable,str(Path('work/check_native_package.py').resolve())],check=True)
helper=stage/'Mods/UpdraftElevator'
(helper/'Scripts').mkdir(parents=True,exist_ok=True)
lua=Path('work/native_cost_only.lua').read_text(encoding='utf-8')
import re
heights=', '.join('CodexWindNative'+v['Suffix']+'='+str(v['LiftHeightCm']) for v in variants)
lua,count=re.subn(r'local HEIGHTS = \{[^\n]+\}', 'local HEIGHTS = {'+heights+'}', lua)
assert count==1
(helper/'Scripts/main.lua').write_text(lua,encoding='utf-8')
shutil.copy2('work/wind_config.lua',helper/'Scripts/config.lua')
(helper/'enabled.txt').write_text('',encoding='utf-8')
readme=Path('work/wind_readme.txt').read_text(encoding='utf-8')
(stage/'使用说明.txt').write_text(readme,encoding='utf-8')
out=Path('outputs'); out.mkdir(exist_ok=True)
(out/'上升气流-v9-说明.txt').write_text(readme,encoding='utf-8')
archive=out/'UpdraftElevator-v9'
shutil.make_archive(str(archive),'zip',stage)
report={'Name':'Updraft Elevator','Version':9,'ConfigFile':'Mods/UpdraftElevator/Scripts/config.lua','Variants':variants,'TechnologyId':'CodexWindTechnology','TechnologyLevel':9,'IsAncientTechnology':True,'TechnologyCost':1,'MaterialCosts':{'Pal_crystal_S':10,'Stone':30,'PalCrystal_Ex':3},'Assets':sorted(expected),'PakEntries':sorted(entries),
        'PakSHA256':hashlib.sha256(pak.read_bytes()).hexdigest(),'GameTest':'v7 gameplay confirmed; v8 configuration regression passed; v9 copy simplified'}
(out/'UpdraftElevator-v9-manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('Built v9 package:',archive.with_suffix('.zip').resolve())
if '--stage-only' in sys.argv: raise SystemExit(0)
running=subprocess.check_output(['tasklist','/FI','IMAGENAME eq Palworld-Win64-Shipping.exe','/NH'])
if b'Palworld-Win64-Shipping.exe' in running:
    raise SystemExit('Package ready. Save and exit Palworld before installing the mounted PAK.')
from palmods import UE4SS_ROOT
mods=UE4SS_ROOT/'Mods'
assert not (mods/'PaltopolisWindElevator/enabled.txt').exists()
backup=Path('work/native-install-backup-'+datetime.now().strftime('%Y%m%d-%H%M%S'))
backup.mkdir()
# Migrate the old folder names once; preserve user height settings.
for old_rel, new_rel in [('CodexWindNativeMenu', 'UpdraftElevator'),
                         ('PalSchema/mods/WindNativePrototype', 'PalSchema/mods/UpdraftElevator')]:
    old_dir, new_dir = mods/old_rel, mods/new_rel
    if old_dir.exists():
        assert old_dir.resolve().is_relative_to(mods.resolve())
        assert not new_dir.exists(), f'Both old and new mod folders exist: {old_rel}, {new_rel}'
        shutil.copytree(old_dir, backup/old_dir.name)
        old_dir.rename(new_dir)
old_pak = mods/'PalSchema/mods/UpdraftElevator/paks/CodexWindNative_P.pak'
if old_pak.exists():
    assert not old_pak.with_name('UpdraftElevator_P.pak').exists()
    old_pak.rename(old_pak.with_name('UpdraftElevator_P.pak'))
legacy_installed=mods/'PalSchema/mods/WindBuildMenu'
if legacy_installed.exists():
    assert legacy_installed.resolve().is_relative_to(mods.resolve())
    shutil.move(str(legacy_installed),str(backup/'WindBuildMenu'))
for rel in ['PalSchema/mods/UpdraftElevator','UpdraftElevator']:
    src=stage/'Mods'/rel; dest=mods/rel
    if dest.exists(): shutil.copytree(dest,backup/'installed'/rel)
    preserve_config=rel=='UpdraftElevator' and (dest/'Scripts/config.lua').is_file()
    def ignore_config(directory,names):
        return ['config.lua'] if preserve_config and Path(directory)==src/'Scripts' else []
    shutil.copytree(src,dest,dirs_exist_ok=True,ignore=ignore_config)
for rel in ['PalSchema/mods/UpdraftElevator/paks/UpdraftElevator_P.pak',
            'PalSchema/mods/UpdraftElevator/buildings/wind_small.json','UpdraftElevator/Scripts/main.lua']:
    assert (mods/rel).read_bytes()==(stage/'Mods'/rel).read_bytes()
assert not legacy_installed.exists()
assert (mods/'UpdraftElevator/Scripts/config.lua').is_file()
print('Installed v9. PAK SHA256:',report['PakSHA256'])
print('Backup:',backup.resolve())
