"""Verify all ranks and every supported multiplier without loading the game."""
import json
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / 'tools'))
from schema_config import patches

base = json.loads((root / 'mod/Config/arena_rewards.base.json').read_text(encoding='utf-8'))
snapshot = json.dumps(base, sort_keys=True)
for multiplier in range(1, 11):
    rewards, points = patches(base, multiplier)
    for rank, original in base['DT_ArenaSoloRewardTable'].items():
        for field in ('FirstClearReward', 'RepeatClearReward'):
            for old, new in zip(original[field], rewards['DT_ArenaSoloRewardTable'][rank][field], strict=True):
                assert new['ItemName'] == old['ItemName'] and new['Rate'] == old['Rate']
                assert new['Min'] == old['Min'] * multiplier and new['Max'] == old['Max'] * multiplier
    assert points == {'BP_PalGameSetting_C': {'Arena_RankPoint_WinToNPC': 50 * multiplier}}
assert json.dumps(base, sort_keys=True) == snapshot
for bad in (0, 11, 1.5, '2', True, float('inf'), float('nan')):
    try:
        patches(base, bad)
    except ValueError:
        pass
    else:
        raise AssertionError(f'Accepted invalid multiplier: {bad}')
print('PASS: PalSchema first/repeat rewards for seven ranks, integer multipliers 1..10, unchanged IDs/probabilities and NPC-only RP')
