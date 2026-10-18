"""Exercise package contents and unsafe/error paths without installing mods."""
import contextlib
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import package_workshop as workshop


class WorkshopTests(unittest.TestCase):
    def test_better_arena_installs_automatic_configuration_and_shared_reward_patches(self):
        if not (workshop.BUILD_ROOT / 'BetterArena/schema/raw/arena_rewards.json').is_file():
            self.skipTest('Run tools/build.py BetterArena to check generated reward patches')
        files = dict((dest, src) for src, dest in workshop.payload('BetterArena'))
        required = {'Scripts/BetterArena/BaseRewards.lua', 'Scripts/BetterArena/Schema.lua',
                    'Scripts/config.lua', 'enabled.txt',
                    'PalSchema/raw/arena_rewards.json', 'PalSchema/blueprints/arena_points.json'}
        self.assertTrue(required <= files.keys())
        rewards = workshop.read_json(files['PalSchema/raw/arena_rewards.json'])
        base = workshop.read_json(workshop.MODS_ROOT / 'BetterArena/mod/Config/arena_rewards.base.json')
        for rank, row in base['DT_ArenaSoloRewardTable'].items():
            for field in ('FirstClearReward', 'RepeatClearReward'):
                expected = [dict(item, Min=item['Min'] * 2, Max=item['Max'] * 2) for item in row[field]]
                self.assertEqual(rewards['DT_ArenaSoloRewardTable'][rank][field], expected)
        self.assertEqual(workshop.read_json(files['PalSchema/blueprints/arena_points.json']),
                         {key: {'Arena_RankPoint_WinToNPC': 100}
                          for key in ('BP_PalGameSetting_C', '/Game/Pal/Blueprint/System/BP_PalGameSetting')})
        info = workshop.read_json(workshop.MODS_ROOT / 'BetterArena/workshop/Info.json')
        lua_targets = next(rule['Targets'] for rule in info['InstallRule'] if rule['Type'] == 'Lua')
        self.assertEqual(lua_targets, ['./Scripts', './enabled.txt'])
        self.assertEqual(info['Dependencies'], ['UE4SSExperimentalPW', 'PalSchema'])

    def test_readme_listing_conversion_and_missing_body(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            for language in workshop.LANGUAGES:
                (folder / f'README.{language}.md').write_text(
                    '# Sample mod\n\n1.0.0 · author\n\n## Usage\n\nUse `Hotkey = "K"`.\n', encoding='utf-8')
            listings = workshop.generate_listings(folder)
            self.assertEqual(listings['en']['Title'], 'Sample mod')
            self.assertTrue(listings['en']['Description'].startswith(
                '[b]1.0.0 · author[/b]\n\n[h2]Usage[/h2]\n\nUse [b][noparse]Hotkey = "K"[/noparse][/b].\n\n'))
            self.assertIn('[h2]Report a problem[/h2]', listings['en']['Description'])
            self.assertIn('[h2]Source code[/h2]', listings['en']['Description'])
            (folder / 'README.en.md').write_text('# Sample mod\n\n1.0.0 · author\n', encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'README.en.md'):
                workshop.generate_listings(folder)

    def test_shared_footer_is_localized_dependency_aware_and_not_duplicated(self):
        headings = {'zh-Hans': ('问题反馈', '开源'), 'zh-Hant': ('問題回報', '原始碼'),
                    'ja': ('不具合の報告', 'ソースコード'), 'en': ('Report a problem', 'Source code')}
        for mod in ('AnywherePalBox', 'QuickButcher'):
            source = workshop.MODS_ROOT / mod / 'workshop'
            with tempfile.TemporaryDirectory() as temporary:
                folder = Path(temporary)
                (folder / 'Info.json').write_bytes((source / 'Info.json').read_bytes())
                for language, titles in headings.items():
                    path = source / f'README.{language}.md'
                    original = path.read_text(encoding='utf-8-sig')
                    self.assertNotIn('https://github.com/ourongxing/PalMods/issues', original)
                    rendered = workshop.render_readme(source, language)
                    for title in titles:
                        self.assertEqual(rendered.count('## ' + title), 1)
                    self.assertEqual(rendered.count('GPL-3.0'), 1)
                    self.assertEqual(rendered.count('https://github.com/ourongxing/PalMods/issues'), 1)
                    self.assertEqual('UE4SS.log' in rendered, mod == 'AnywherePalBox')
                    self.assertNotIn('{{runtime_logs}}', rendered)
                    (folder / path.name).write_text(rendered, encoding='utf-8')
                    self.assertEqual(workshop.render_readme(folder, language), rendered)

    def test_template_changes_flow_into_generated_listings(self):
        with tempfile.TemporaryDirectory() as temporary:
            templates = Path(temporary)
            for language in workshop.LANGUAGES:
                (templates / f'README.{language}.md').write_text('## Shared support\n\nFirst footer', encoding='utf-8')
            source = workshop.MODS_ROOT / 'QuickButcher/workshop'
            with patch.object(workshop, 'TEMPLATES_ROOT', templates):
                first = workshop.generate_listings(source)
                for language in workshop.LANGUAGES:
                    (templates / f'README.{language}.md').write_text('## Shared support\n\nUpdated footer', encoding='utf-8')
                updated = workshop.generate_listings(source)
            for language in workshop.LANGUAGES:
                self.assertEqual(first[language]['Title'], updated[language]['Title'])
                self.assertIn('Updated footer', updated[language]['Description'])
                self.assertNotIn('First footer', updated[language]['Description'])

    def test_steam_format_headings_lists_links_and_literal_code(self):
        self.assertEqual(workshop.steam_format_markdown(
            '## Features\n\n- **First**\n- [Guide](https://example.com/guide)\n\n'
            '1. Install\n2. Restart\n\n### Config\n\nUse `value[b]`.'),
            '[h2]Features[/h2]\n\n[list]\n[*][b]First[/b]\n'
            '[*][url=https://example.com/guide]Guide[/url]\n[/list]\n\n'
            '[olist]\n[*]Install\n[*]Restart\n[/olist]\n\n'
            '[h3]Config[/h3]\n\nUse [b][noparse]value[b][/noparse][/b].')
        self.assertEqual(workshop.steam_format_markdown('- First\n- Last'),
                         '[list]\n[*]First\n[*]Last\n[/list]')

    def test_listings_only_needs_no_build_and_preflights_all_languages(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / 'output'
            with patch.object(workshop, 'payload', side_effect=AssertionError('Build inputs requested')):
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(workshop.main(['--listings-only', '--output-root', str(output)]), 0)
            for mod in workshop.MODS:
                self.assertEqual(workshop.read_json(output / mod / 'listing.json'),
                                 workshop.generate_listings(workshop.MODS_ROOT / mod / 'workshop'))
            self.assertEqual(len(list(output.rglob('*.*'))), len(workshop.MODS))
            with contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(workshop.main(['--listings-only', '--output-root', str(output)]), 1)
            missing_output = Path(temporary) / 'missing-output'
            with patch.object(workshop, 'generate_listings', side_effect=[{}, ValueError('Missing body')]):
                with contextlib.redirect_stderr(io.StringIO()):
                    self.assertEqual(workshop.main(['--listings-only', '--output-root', str(missing_output)]), 1)
            self.assertFalse(missing_output.exists())

    def test_no_mod_arguments_selects_all(self):
        with patch.object(workshop, 'prepare', return_value=({}, [])) as prepare:
            with patch.object(workshop, 'package_mod') as package:
                with tempfile.TemporaryDirectory() as temporary, contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(workshop.main(['--output-root', temporary]), 0)
        self.assertEqual([call.args[0] for call in prepare.call_args_list], list(workshop.MODS))
        self.assertEqual(package.call_count, len(workshop.MODS))

    def test_packages_deploy_to_expected_runtime_layout(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            for mod in workshop.MODS:
                # Uses actual build inputs; skip only if a developer has not built yet.
                try:
                    plan = workshop.prepare(mod)
                except FileNotFoundError as error:
                    self.skipTest(str(error))
                package = workshop.package_mod(mod, plan, output)
                info = workshop.validate(package)
                expected_listings = workshop.generate_listings(workshop.MODS_ROOT / mod / 'workshop')
                self.assertEqual(workshop.read_json(package / 'listing.json'), expected_listings)
                for language in workshop.LANGUAGES:
                    rendered = (package / f'README.{language}.md').read_text(encoding='utf-8')
                    self.assertTrue(rendered.strip().endswith(workshop.common_footer(package, language)))
                    self.assertEqual(rendered.count('GPL-3.0'), 1)
                installed = set()
                installed_by_server = {False: set(), True: set()}
                for rule in info['InstallRule']:
                    base = {'Lua': 'Mods/NativeMods/UE4SS/Mods/' + mod,
                            'PalSchema': 'Mods/NativeMods/UE4SS/Mods/PalSchema/mods/' + mod,
                            'Paks': 'Pal/Content/Paks/~WorkshopMods/' + mod}[rule['Type']]
                    for target in rule['Targets']:
                        source = package / target
                        paths = list(source.rglob('*')) if source.is_dir() else [source]
                        for file in paths:
                            if file.is_file():
                                relative = file.relative_to(source if target.endswith('/') else source.parent).as_posix()
                                installed.add(base + '/' + relative)
                                installed_by_server[rule.get('IsServer', False)].add(base + '/' + relative)
                lua_root = f'Mods/NativeMods/UE4SS/Mods/{mod}'
                if mod not in ('PointBlankBurstSkills', 'QuickButcher'):
                    if mod != 'ExtraImplantDrops':
                        self.assertIn(lua_root + '/Scripts/main.lua', installed)
                    self.assertIn(lua_root + '/enabled.txt', installed)
                if mod in ('BetterWorkbench', 'PalCombo', 'BetterBulkStorage', 'BetterStorage', 'ExtraImplantDrops', 'CustomPresets'):
                    self.assertIn(lua_root + '/dlls/main.dll', installed)
                if mod == 'CustomPresets':
                    self.assertEqual(info['Version'], '1.0.0')
                    self.assertEqual(info['Dependencies'], ['UE4SSExperimentalPW'])
                    self.assertFalse(any('/presets/' in path for path in installed))
                    self.assertTrue((package / 'Scripts/CustomPresets/UI.lua').is_file())
                if mod in ('PalCombo', 'ExtraImplantDrops'):
                    self.assertIn(lua_root + '/config.ini', installed)
                if mod == 'ExtraImplantDrops':
                    self.assertFalse(any('/Scripts/' in path for path in installed))
                    self.assertEqual(info['Version'], '1.0.0')
                if mod == 'AnywherePalBox':
                    self.assertIn(lua_root + '/Scripts/config.lua', installed)
                    self.assertEqual(info['Dependencies'], ['UE4SSExperimentalPW'])
                    self.assertFalse(any('/dlls/' in path or '/PalSchema/' in path for path in installed))
                if mod == 'UpdraftElevator':
                    self.assertEqual(info['Version'], '1.1.1')
                    self.assertEqual(len(info['InstallRule']), 4)
                    for server in (False, True):
                        self.assertEqual({rule['Type'] for rule in info['InstallRule']
                                          if rule.get('IsServer', False) == server}, {'Lua', 'PalSchema'})
                    self.assertEqual(installed_by_server[True], installed_by_server[False])
                    self.assertIn('Mods/NativeMods/UE4SS/Mods/PalSchema/mods/UpdraftElevator/paks/UpdraftElevator_P.pak', installed)
                    self.assertIn('Mods/NativeMods/UE4SS/Mods/PalSchema/mods/UpdraftElevator/buildings/wind_small.json', installed)
                    self.assertIn('Mods/NativeMods/UE4SS/Mods/PalSchema/mods/UpdraftElevator/translations/zh-Hans/updraft.json', installed)
                if mod == 'PointBlankBurstSkills':
                    self.assertIn('Mods/NativeMods/UE4SS/Mods/PalSchema/mods/PointBlankBurstSkills/raw/point_blank_burst_skills.json', installed)
                if mod == 'BetterStorage':
                    self.assertIn('Mods/NativeMods/UE4SS/Mods/PalSchema/mods/BetterStorage/blueprints/storage.json', installed)
                    self.assertEqual(info['Dependencies'], ['UE4SSExperimentalPW', 'PalSchema'])
                    self.assertEqual(info['Version'], '1.1.0')
                if mod == 'QuickButcher':
                    self.assertEqual(installed, {'Pal/Content/Paks/~WorkshopMods/QuickButcher/QuickButcher_P.pak'})
                    self.assertEqual(info['Dependencies'], [])
                    self.assertEqual(info['Version'], '1.0.0')
                manifest = workshop.read_json(package / 'package-manifest.json')
                with zipfile.ZipFile(output / (mod + '.zip')) as archive:
                    self.assertIsNone(archive.testzip())
                    self.assertIn('Info.json', archive.namelist())
                    self.assertNotIn('README.md', archive.namelist())
                    for name, sha in manifest['Files'].items():
                        self.assertEqual(workshop.digest(package / name), sha)
                        self.assertEqual(archive.read(name), (package / name).read_bytes())
                    self.assertFalse(any('Jobs/' in name or name == 'mods.txt' for name in archive.namelist()))
                with self.assertRaises(FileExistsError):
                    workshop.package_mod(mod, plan, output)

    def make_schema_package(self, folder):
        template = workshop.MODS_ROOT / 'PointBlankBurstSkills/workshop'
        info = workshop.read_json(template / 'Info.json')
        (folder / 'Info.json').write_text(json.dumps(info), encoding='utf-8')
        (folder / 'thumbnail.png').write_bytes((template / 'thumbnail.png').read_bytes())
        for language in workshop.LANGUAGES:
            (folder / f'README.{language}.md').write_bytes((template / f'README.{language}.md').read_bytes())
        workshop.write_listings(folder, workshop.generate_listings(folder))
        (folder / 'PalSchema/raw').mkdir(parents=True)
        return info

    def test_reject_stale_listing(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            self.make_schema_package(folder)
            listings = workshop.read_json(folder / 'listing.json')
            listings['en']['Description'] = 'Stale description'
            workshop.write_listings(folder, listings)
            with self.assertRaisesRegex(ValueError, 'differs from localized READMEs'):
                workshop.validate(folder)

    def test_reject_missing_targets_traversal_and_wrong_schema_nesting(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            info = self.make_schema_package(folder)
            for target in ('../outside', 'C:/outside', './missing', './PalSchema/PointBlankBurstSkills', './PalSchema'):
                info['InstallRule'][0]['Targets'] = [target]
                (folder / 'Info.json').write_text(json.dumps(info), encoding='utf-8')
                with self.subTest(target=target), self.assertRaises(ValueError):
                    workshop.validate(folder)

    def test_server_rules_validate_targets_and_require_boolean_flag(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            info = self.make_schema_package(folder)
            info['InstallRule'][0]['IsServer'] = True
            (folder / 'Info.json').write_text(json.dumps(info), encoding='utf-8')
            self.assertEqual(workshop.validate(folder), info)
            for target in ('../outside', './missing', './PalSchema'):
                info['InstallRule'][0]['Targets'] = [target]
                (folder / 'Info.json').write_text(json.dumps(info), encoding='utf-8')
                with self.subTest(target=target), self.assertRaises(ValueError):
                    workshop.validate(folder)
            info['InstallRule'][0]['Targets'] = ['./PalSchema/']
            for flag in ('true', 1, None):
                info['InstallRule'][0]['IsServer'] = flag
                (folder / 'Info.json').write_text(json.dumps(info), encoding='utf-8')
                with self.subTest(flag=flag), self.assertRaisesRegex(ValueError, 'IsServer must be a boolean'):
                    workshop.validate(folder)

    def test_missing_native_input_fails_before_emitting_any_package(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / 'output'
            with patch.object(workshop, 'prepare', side_effect=FileNotFoundError('Missing DLL')):
                with contextlib.redirect_stderr(io.StringIO()):
                    self.assertEqual(workshop.main(['all', '--output-root', str(output)]), 1)
            self.assertFalse(output.exists())

    def test_audit_mismatch_rejects_changed_workbench_dll(self):
        with tempfile.TemporaryDirectory() as temporary:
            build = Path(temporary)
            folder = build / 'BetterWorkbench/native/Release'
            folder.mkdir(parents=True)
            (folder / 'BetterWorkbenchNative.dll').write_bytes(b'changed')
            (build / 'BetterWorkbench/import-audit.json').write_text(json.dumps({
                'bridge_sha256': '0' * 64, 'ue4ss_imports_verified': 67}), encoding='utf-8')
            with patch.object(workshop, 'BUILD_ROOT', build), self.assertRaisesRegex(ValueError, 'differs'):
                workshop.payload('BetterWorkbench')

    def test_pak_payload_rejects_changed_artifact(self):
        with tempfile.TemporaryDirectory() as temporary:
            dist = Path(temporary)
            folder = dist / 'QuickButcher'
            folder.mkdir()
            (folder / 'QuickButcher_P.pak').write_bytes(b'changed')
            (folder / 'build-audit.json').write_text(json.dumps({
                'Mod': 'QuickButcher', 'PakSHA256': '0' * 64}), encoding='utf-8')
            with patch.object(workshop, 'DIST_ROOT', dist), self.assertRaisesRegex(ValueError, 'differs'):
                workshop.payload('QuickButcher')

    def test_paks_rule_rejects_missing_slash_empty_folder_and_file_target(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            info = self.make_schema_package(folder)
            (folder / 'Paks').mkdir()
            info['InstallRule'] = [{'Type': 'Paks', 'Targets': ['./Paks/']}]
            (folder / 'Info.json').write_text(json.dumps(info), encoding='utf-8')
            with self.assertRaisesRegex(ValueError, 'Paks target'):
                workshop.validate(folder)
            (folder / 'Paks/test.pak').write_bytes(b'package')
            for target in ('./Paks', './Paks/test.pak'):
                info['InstallRule'][0]['Targets'] = [target]
                (folder / 'Info.json').write_text(json.dumps(info), encoding='utf-8')
                with self.subTest(target=target), self.assertRaisesRegex(ValueError, 'Paks target'):
                    workshop.validate(folder)
            info['InstallRule'][0]['Targets'] = ['./Paks/']
            (folder / 'Info.json').write_text(json.dumps(info), encoding='utf-8')
            self.assertEqual(workshop.validate(folder), info)


if __name__ == '__main__':
    unittest.main()
