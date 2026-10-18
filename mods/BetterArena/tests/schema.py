"""Verify all ranks and every supported multiplier without loading the game."""
import json
from pathlib import Path
import sys
import tempfile

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root / 'tools'))
from schema_config import patches
sys.path.insert(0, str(root.parents[1] / 'tools'))
from palmods import load_lua_runtime
lua = load_lua_runtime()(unpack_returned_tuples=True)
lua.execute('package.path=... .. "/mod/Scripts/?.lua;" .. package.path', root.as_posix())
lua_base = lua.eval('require("BetterArena.BaseRewards")')[0]
schema = lua.eval('require("BetterArena.Schema")')[0]
with tempfile.TemporaryDirectory() as temporary:
    config_path = Path(temporary) / 'config.json'
    original = {'enableAutoReload': False, 'languageOverride': 'ja', 'enableDebugLogging': True, 'other': 123}
    config_path.write_text(json.dumps(original), encoding='utf-8')
    assert schema.autoReload(config_path.as_posix()) is False
    expected_config = dict(original, enableAutoReload=True)
    assert json.loads(config_path.read_text()) == expected_config
    assert schema.autoReload(config_path.as_posix()) is True
    config_path.write_text('{"other": true}', encoding='utf-8')
    try:
        schema.autoReload(config_path.as_posix())
    except Exception:
        pass
    else:
        raise AssertionError('Missing reload setting accepted')
    assert config_path.read_text() == '{"other": true}'

base = json.loads((root / 'mod/Config/arena_rewards.base.json').read_text(encoding='utf-8'))
snapshot = json.dumps(base, sort_keys=True)
for multiplier in range(1, 11):
    rewards, points = patches(base, multiplier)
    raw_text, point_text = schema.patches(lua_base, multiplier)
    assert json.loads(raw_text) == rewards
    assert json.loads(point_text) == points
    for rank, original in base['DT_ArenaSoloRewardTable'].items():
        for field in ('FirstClearReward', 'RepeatClearReward'):
            for old, new in zip(original[field], rewards['DT_ArenaSoloRewardTable'][rank][field], strict=True):
                assert new['ItemName'] == old['ItemName'] and new['Rate'] == old['Rate']
                assert new['Min'] == old['Min'] * multiplier and new['Max'] == old['Max'] * multiplier
    assert points == {key: {'Arena_RankPoint_WinToNPC': 50 * multiplier}
                      for key in ('BP_PalGameSetting_C', '/Game/Pal/Blueprint/System/BP_PalGameSetting')}
assert json.dumps(base, sort_keys=True) == snapshot
for bad in (0, 11, 1.5, '2', True, float('inf'), float('nan')):
    try:
        patches(base, bad)
    except ValueError:
        pass
    else:
        raise AssertionError(f'Accepted invalid multiplier: {bad}')
print('PASS: PalSchema first/repeat rewards for seven ranks, integer multipliers 1..10, unchanged IDs/probabilities and NPC-only RP')
