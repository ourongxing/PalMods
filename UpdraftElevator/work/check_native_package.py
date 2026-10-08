from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from palmods import use_mod_directory
use_mod_directory('UpdraftElevator')
import json
from jsonschema import Draft7Validator
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT7
schema_dir=Path('work/data/schema').resolve()
schema=json.loads((schema_dir/'buildings.schema.json').read_text(encoding='utf-8'))
schema['$id']=(schema_dir/'buildings.schema.json').as_uri()
registry=Registry().with_resources(
    (path.as_uri(), Resource.from_contents(json.loads(path.read_text(encoding='utf-8')), default_specification=DRAFT7))
    for path in schema_dir.glob('*.json')
)
from wind_data import build_rows
rows=build_rows()
staged=Path('work/native-package/Mods/PalSchema/mods/UpdraftElevator/buildings/wind_small.json')
if staged.is_file():
    assert json.loads(staged.read_text(encoding='utf-8')) == rows, 'Staged metadata is out of date'
errors=sorted(Draft7Validator(schema,registry=registry).iter_errors(rows),key=lambda e:str(e.path))
for error in errors: print(list(error.path),error.message)
assert not errors
# PalSchema runtime Add() enforces these fields beyond its published JSON schema.
for bid,row in rows.items():
    for field in ['BlueprintClassName','BlueprintClassSoft','IconTexture']:
        assert row.get(field), f'{bid}: runtime-required {field} absent'
variants=json.loads(Path('work/wind_variants.json').read_text(encoding='utf-8'))
assert set(rows)=={'CodexWindNative'+v['Suffix'] for v in variants}|{'CodexWindTechnology'}
tech=rows['CodexWindTechnology']
assert 'BuildingData' not in tech
assert tech['Technology']['Name']=='上升气流' and tech['Technology']['Cost']==1
assert tech['Technology']['LevelCap']==9 and tech['Technology']['IsBossTechnology']==True
assert tech['Technology']['UnlockBuildObjects']==['CodexWindNative'+v['Suffix'] for v in variants]
assert sum('Technology' in row for row in rows.values())==1
assert not Path('work/native-package/Mods/PalSchema/mods/WindBuildMenu').exists()
for v in variants:
    bid='CodexWindNative'+v['Suffix']; row=rows[bid]
    assert 'Technology' not in row
    assert row['BuildingData']['SortId']==v['SortId']
    assert row['BuildingData']['Material1_Id']=='Pal_crystal_S' and row['BuildingData']['Material1_Count']==10
    assert row['BuildingData']['Material2_Id']=='Stone' and row['BuildingData']['Material2_Count']==30
    assert row['BuildingData']['Material3_Id']=='PalCrystal_Ex' and row['BuildingData']['Material3_Count']==3
    assert row['BuildingData']['Material4_Id']=='None' and row['BuildingData']['Material4_Count']==0
    icon=Path('work/wind-art')/('T_WindIcon'+v['Suffix']+'.png')
    assert icon.is_file(), f'Missing source artwork: {icon}'
print('PASS: runtime required fields, level 9 ancient technology costs 1, all 3 sizes cost 10 Paldium + 30 Stone + 3 Ancient Civilization Parts, old technologies absent')
