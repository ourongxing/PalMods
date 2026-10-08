"""Current building metadata, independent of retired packages or cooked assets."""
from copy import deepcopy
from pathlib import Path
import json

WORK = Path(__file__).resolve().parents[1]


def build_rows():
    template = json.loads((WORK / 'data/building_template.json').read_text(encoding='utf-8'))
    variants = json.loads((WORK / 'data/variants.json').read_text(encoding='utf-8'))
    rows = {}
    for variant in variants:
        suffix = variant['Suffix']
        row = deepcopy(template)
        # Names and descriptions are supplied by language tables, not global overrides.
        row.pop('Name', None)
        row.pop('Description', None)
        row['BlueprintClassName'] = 'BP_Wind' + suffix
        row['BlueprintClassSoft'] = f'/Game/Mods/CodexWindNative/BP_Wind{suffix}.BP_Wind{suffix}_C'
        row['IconTexture'] = f'/Game/Mods/CodexWindNative/Textures/T_WindIcon{suffix}.T_WindIcon{suffix}'
        row['BuildingData']['SortId'] = variant['SortId']
        rows['CodexWindNative' + suffix] = row
    small = rows['CodexWindNativeSmall']
    rows['CodexWindTechnology'] = {
        **{field: small[field] for field in ('BlueprintClassName', 'BlueprintClassSoft', 'IconTexture')},
        'bInDevelop': True,
        'Technology': {
            'UnlockBuildObjects': ['CodexWindNative' + v['Suffix'] for v in variants],
            'IconName': 'CodexWindTechnology', 'LevelCap': 9, 'Cost': 1, 'IsBossTechnology': True,
        },
    }
    return rows


def translation_files():
    return sorted((WORK / 'mod/translations').rglob('*.json'))
