"""Current building metadata, independent of retired packages or cooked assets."""
from copy import deepcopy
from pathlib import Path
import json

WORK = Path(__file__).resolve().parent


def build_rows():
    template = json.loads((WORK / 'data/building_template.json').read_text(encoding='utf-8'))
    variants = json.loads((WORK / 'wind_variants.json').read_text(encoding='utf-8'))
    rows = {}
    for variant in variants:
        suffix = variant['Suffix']
        row = deepcopy(template)
        row['Name'] = f"上升气流 · {variant['Label']}"
        row['Description'] = f"在直径{variant['RadiusCm'] * 2 // 100}米的气流区域内起跳升空。"
        row['BlueprintClassName'] = 'BP_Wind' + suffix
        row['BlueprintClassSoft'] = f'/Game/Mods/CodexWindNative/BP_Wind{suffix}.BP_Wind{suffix}_C'
        row['IconTexture'] = f'/Game/Mods/CodexWindNative/Textures/T_WindIcon{suffix}.T_WindIcon{suffix}'
        row['BuildingData']['SortId'] = variant['SortId']
        rows['CodexWindNative' + suffix] = row
    small = rows['CodexWindNativeSmall']
    rows['CodexWindTechnology'] = {
        'Name': '上升气流',
        **{field: small[field] for field in ('BlueprintClassName', 'BlueprintClassSoft', 'IconTexture')},
        'bInDevelop': True,
        'Technology': {
            'Name': '上升气流', 'Description': '解锁小、中、大型上升气流。',
            'UnlockBuildObjects': ['CodexWindNative' + v['Suffix'] for v in variants],
            'IconName': 'CodexWindTechnology', 'LevelCap': 9, 'Cost': 1, 'IsBossTechnology': True,
        },
    }
    return rows
