"""Audit dynamic eligibility and Trust balance from an extracted vanilla table."""
import argparse
import csv
import json
import math
from pathlib import Path

FIELDS = ('Friendship_HP', 'Friendship_ShotAttack', 'Friendship_Defense')
BASE = ('Hp', 'ShotAttack', 'Defense')
TARGET = 450.0


def rebalance(base, growth):
    final = [b + 10 * g for b, g in zip(base, growth)]
    total = sum(final)
    if not all(math.isfinite(v) and v > 0 for v in base + final):
        raise ValueError('Invalid vanilla stats')
    if total >= TARGET:
        return None
    return [max(g, (f * TARGET / total - b) / 10)
            for b, g, f in zip(base, growth, final)]


def select_rows(rows):
    return {key for key, p in rows.items()
            if p.get('IsPal') and not p.get('IsUncapturable')}


def generate(source):
    data = json.loads(Path(source).read_text(encoding='utf-8-sig'))
    rows = {r['Name']: {v['Name']: v['Value'] for v in r['Value']}
            for r in data['Exports'][0]['Table']['Data']}
    selected = select_rows(rows)
    changed, audit = set(), []
    for key in sorted(selected):
        p = rows[key]
        base = [float(p[k]) for k in BASE]
        growth = [float(p[k]) for k in FIELDS]
        new = rebalance(base, growth)
        if new is not None:
            changed.add(key)
        old_final = [b + 10*g for b, g in zip(base, growth)]
        new_final = [b + 10*g for b, g in zip(base, new or growth)]
        audit.append([key, sum(old_final), sum(new_final), *old_final, *new_final])
    return changed, audit, len(selected)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--audit', type=Path, required=True)
    args = parser.parse_args()
    changed, audit, count = generate(args.source)
    args.audit.parent.mkdir(parents=True, exist_ok=True)
    with args.audit.open('w', newline='', encoding='utf-8-sig') as stream:
        writer = csv.writer(stream)
        writer.writerow(['ID', 'OldTotal', 'NewTotal', 'OldHP', 'OldAttack', 'OldDefense', 'NewHP', 'NewAttack', 'NewDefense'])
        writer.writerows(audit)
    print(f'{count} eligible rows, {len(changed)} changed')


if __name__ == '__main__':
    main()
