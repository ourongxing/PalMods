"""Compare observed native UI demands with a LOCAL cooked recipe export.

This diagnoses runtime cost differences. It never treats UI observations as
authoritative inventory, per-batch server costs, or permission to debit.
"""
from pathlib import Path
import argparse
import json
import re
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from palmods import UE4SS_ROOT, GAME_DATA_ROOT, build_directory

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--log", type=Path, default=UE4SS_ROOT / 'UE4SS.log')
parser.add_argument("--recipes", type=Path, default=GAME_DATA_ROOT / 'recipes.json')
parser.add_argument("--output", type=Path, default=build_directory('BetterWorkbench') / 'ui-cost-comparison.json')
args = parser.parse_args()
asset = json.loads(args.recipes.read_text(encoding="utf-8-sig"))
tables = [x for x in asset["Exports"] if "DataTableExport" in x["$type"]]
assert len(tables) == 1, "Expected one recipe table"
recipes = {row["Name"]: {field["Name"]: field.get("Value") for field in row["Value"]}
           for row in tables[0]["Table"]["Data"]}
observed = {}
for line in args.log.read_text(encoding="utf-8", errors="replace").splitlines():
    match = re.search(r"\[([^]]+)\].*UI_MATERIALS recipe=(\S+) costs=([^\r\n]*)$", line)
    if not match:
        continue
    timestamp, recipe_id, text = match.groups()
    costs = {}
    for token in text.split(",") if text else []:
        item, value = token.rsplit("=", 1)
        amount = int(value)
        assert item and 0 < amount <= 1000000000 and item not in costs, "Invalid UI log entry"
        costs[item] = amount
    raw = {}
    row = recipes.get(recipe_id)
    if row:
        for index in range(1, 6):
            item, amount = row.get(f"Material{index}_Id"), row.get(f"Material{index}_Count")
            if item not in (None, "None") and amount:
                raw[item] = raw.get(item, 0) + amount
    observed[recipe_id] = {"Recipe": recipe_id, "Timestamp": timestamp,
                           "Raw": raw if row else None, "NativeUI": costs,
                           "Equal": raw == costs if row else None}
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(list(observed.values()), ensure_ascii=False, indent=2), encoding="utf-8")
differences = [x for x in observed.values() if x["Equal"] is False]
print(f"Observed {len(observed)} native UI recipes; {len(differences)} differ from cooked costs.")
for row in differences:
    print(f"{row['Recipe']}: raw={row['Raw']} native UI={row['NativeUI']}")
print("UI demands are observations only; server batch costs and inventory remain unverified.")
