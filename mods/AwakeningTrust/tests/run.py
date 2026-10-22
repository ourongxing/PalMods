"""Verify the balance rule, float32 storage, and optional full vanilla-table audit."""
import importlib.util
import struct
import unittest
from pathlib import Path

MOD = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('bond_generate', MOD / 'tools/generate.py')
rules = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rules)


class BalanceTests(unittest.TestCase):
    def test_new_species_and_exclusions(self):
        normal = {'IsPal': True, 'IsUncapturable': False, 'ZukanIndex': 999}
        unindexed = dict(normal, ZukanIndex=-1)
        rows = {'FuturePal': normal, 'BOSS_FuturePal': unindexed,
                'FuturePlaceholder': unindexed, 'BOSS_FuturePlaceholder': unindexed,
                'Uncatchable': dict(normal, IsUncapturable=True),
                'Human': dict(normal, IsPal=False), 'YakushimaFuture': unindexed}
        self.assertEqual(rules.select_rows(rows), {'FuturePal', 'BOSS_FuturePal', 'FuturePlaceholder', 'BOSS_FuturePlaceholder', 'YakushimaFuture'})

    def check_balance(self, base, growth):
        new = rules.rebalance(base, growth)
        final = [b+10*g for b, g in zip(base, growth)]
        if sum(final) >= 450:
            self.assertIsNone(new)
            return
        stored = [struct.unpack('f', struct.pack('f', n))[0] for n in new]
        result = [b+10*g for b, g in zip(base, stored)]
        self.assertAlmostEqual(sum(result), 450, delta=0.0001)
        for level in range(11):
            for b, old, n in zip(base, growth, stored):
                self.assertGreaterEqual(b+level*n+0.00001, b+level*old)
        for i in (1, 2):
            self.assertAlmostEqual(result[i]/result[0], final[i]/final[0], places=6)

    def test_representative_and_threshold(self):
        for base, growth in [([70,70,70],[5.5,3.7,3.7]),([115,140,120],[3.3,1,1.7]),
                             ([140,140,135],[2,1,1.1]),([180,120,200],[.1,1.7,1]),
                             ([100,100,100],[5,5,5])]:
            self.check_balance(base, growth)

    def test_full_table_audit(self):
        source = MOD.parents[1] / '.build/trust-stat-audit/parameters-current.json'
        if not source.exists():
            self.skipTest('Local extracted vanilla table unavailable; full-table audit not run')
        changed, audit, count = rules.generate(source)
        self.assertGreaterEqual(count, 598)
        for row in audit:
            old, new = row[3:6], row[6:9]
            if sum(old) >= 450:
                self.assertEqual(old, new)
            else:
                self.assertAlmostEqual(sum(new), 450, places=8)
                self.assertTrue(all(n >= o for n, o in zip(new, old)))
                self.check_balance([1,1,1], [(v-1)/10 for v in old])
        self.assertNotIn('IceHorse_Dark', changed)
        self.assertNotIn('KingWhale', changed)
        # Unindexed rows are now governed solely by their own capture flags.


if __name__ == '__main__':
    unittest.main()
