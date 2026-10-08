"""Exercise language selection, UI format strings and PalSchema translation IDs."""
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from palmods import ROOT, load_lua_runtime


class LocalizationTests(unittest.TestCase):
    def setUp(self):
        self.lua = load_lua_runtime()(unpack_returned_tuples=True)
        source = ROOT / 'mods/BetterWorkbench/mod/Scripts/BetterWorkbench/I18n.lua'
        self.i18n = self.lua.execute(source.read_text(encoding='utf-8'))

    def test_auto_detects_current_game_language_and_changes_without_reload(self):
        self.lua.execute('''
            culture = "ja-JP"
            function StaticFindObject(path)
                assert(path == "/Script/Engine.Default__KismetInternationalizationLibrary")
                return {GetCurrentLanguage=function() return {ToString=function() return culture end} end}
            end
        ''')
        self.assertEqual(self.i18n.text('start'), '分解を開始')
        self.lua.globals().culture = 'zh-Hans-CN'
        self.assertEqual(self.i18n.text('title', '金属铸块'), '分解 · 金属铸块')
        for culture in ('zh-Hant', 'zh-Hant-TW', 'zh_TW', 'zh-HK', 'zh-MO'):
            self.lua.globals().culture = culture
            self.assertEqual(self.i18n.language(), 'zh-Hant')
            self.assertEqual(self.i18n.text('start'), '開始分解')
        self.lua.globals().culture = 'zh-Hans-HK'
        self.assertEqual(self.i18n.language(), 'zh-Hans')
        self.lua.globals().culture = 'en-US'
        self.assertEqual(self.i18n.text('title', 'Ingot'), 'Disassemble: Ingot')
        self.lua.globals().culture = 'fr'
        self.assertEqual(self.i18n.text('start'), 'Start Disassembly')

    def test_override_fallback_and_all_messages_format_in_four_languages(self):
        keys = ('start', 'backpack_full', 'insufficient_products', 'disassembly_in_progress',
                'disassembly_disabled_after_inventory_error', 'retry', 'separator', 'complete')
        for language in ('zh-Hans', 'zh-Hant', 'ja', 'en'):
            self.i18n.configure(language)
            self.assertEqual(self.i18n.language(), language)
            for key in keys:
                self.assertTrue(self.i18n.text(key))
            self.assertIn('Item 100%', self.i18n.text('consumed', 'Item 100%', 3))
            self.assertIn('reason', self.i18n.text('failed', 'reason'))
            self.assertIn('materials', self.i18n.text('returned', 'materials'))
        self.i18n.configure('auto')
        self.lua.execute('StaticFindObject=function() error("engine unavailable") end')
        self.assertEqual(self.i18n.language(), 'en')

    def test_building_translations_cover_every_id_and_do_not_override_vanilla(self):
        sys.path.insert(0, str(ROOT / 'mods/UpdraftElevator/tools'))
        from wind_data import build_rows
        rows = build_rows()
        self.assertTrue(all('Name' not in row and 'Description' not in row for row in rows.values()))
        expected = {
            'DT_MapObjectNameText': {'MAPOBJECT_NAME_' + key for key in rows},
            'DT_BuildObjectDescText': {'BUILDOBJECT_DESC_' + key for key in rows if 'BuildingData' in rows[key]},
            'DT_TechnologyNameText': {'NAME_RECIPE_CodexWindTechnology'},
            'DT_TechnologyDescText': {'DESC_RECIPE_CodexWindTechnology'},
        }
        folder = ROOT / 'mods/UpdraftElevator/mod/translations'
        for language in ('zh-Hans', 'zh-Hant', 'ja', 'en', 'global'):
            data = json.loads((folder / language / 'updraft.json').read_text(encoding='utf-8'))
            self.assertEqual(set(data), set(expected))
            for table, keys in expected.items():
                self.assertEqual(set(data[table]), keys)
                self.assertTrue(all(isinstance(value, str) and value for value in data[table].values()))
        self.assertEqual((folder / 'global/updraft.json').read_bytes(), (folder / 'en/updraft.json').read_bytes())


if __name__ == '__main__':
    unittest.main()
