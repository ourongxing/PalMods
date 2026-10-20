"""Verify patch scope against the decoded 1.0.5.102999 vanilla baseline."""
import json
from pathlib import Path

MOD = Path(__file__).resolve().parents[1]
baseline = json.loads((MOD / 'tests/vanilla_seconds.json').read_text(encoding='utf-8-sig'))
patch = json.loads((MOD / 'mod/raw/expedition_time.json').read_text(encoding='utf-8-sig'))
assert set(patch) == {'DT_CharacterTeamMissionDataTable'}
rows = patch['DT_CharacterTeamMissionDataTable']
assert len(rows) == 18 and rows.keys() == baseline.keys()
for name, fields in rows.items():
    assert set(fields) == {'RequiredSeconds'}, name
    assert type(fields['RequiredSeconds']) is int and fields['RequiredSeconds'] > 0
    assert fields['RequiredSeconds'] * 10 == baseline[name], name
assert {p.suffix for p in (MOD / 'mod').rglob('*') if p.is_file()} == {'.json'}
print('PASS: 18 missions at 10% vanilla duration; only RequiredSeconds changed; no executable runtime.')
