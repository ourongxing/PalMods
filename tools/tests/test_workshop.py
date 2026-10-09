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
                installed = set()
                for rule in info['InstallRule']:
                    base = ('Mods/NativeMods/UE4SS/Mods/' + mod if rule['Type'] == 'Lua'
                            else 'Mods/NativeMods/UE4SS/Mods/PalSchema/mods/' + mod)
                    for target in rule['Targets']:
                        source = package / target
                        paths = list(source.rglob('*')) if source.is_dir() else [source]
                        for file in paths:
                            if file.is_file():
                                relative = file.relative_to(source if rule['Type'] == 'PalSchema' else source.parent).as_posix()
                                installed.add(base + '/' + relative)
                lua_root = f'Mods/NativeMods/UE4SS/Mods/{mod}'
                if mod != 'PointBlankBurstSkills':
                    self.assertIn(lua_root + '/Scripts/main.lua', installed)
                    self.assertIn(lua_root + '/enabled.txt', installed)
                if mod in ('BetterWorkbench', 'PalCombo', 'BetterBulkStorage'):
                    self.assertIn(lua_root + '/dlls/main.dll', installed)
                if mod == 'PalCombo':
                    self.assertIn(lua_root + '/config.ini', installed)
                if mod == 'UpdraftElevator':
                    self.assertIn('Mods/NativeMods/UE4SS/Mods/PalSchema/mods/UpdraftElevator/paks/UpdraftElevator_P.pak', installed)
                if mod == 'PointBlankBurstSkills':
                    self.assertIn('Mods/NativeMods/UE4SS/Mods/PalSchema/mods/PointBlankBurstSkills/raw/point_blank_burst_skills.json', installed)
                manifest = workshop.read_json(package / 'package-manifest.json')
                with zipfile.ZipFile(output / (mod + '.zip')) as archive:
                    self.assertIsNone(archive.testzip())
                    self.assertIn('Info.json', archive.namelist())
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
        (folder / 'listing.json').write_bytes((template / 'listing.json').read_bytes())
        for language in workshop.LANGUAGES:
            (folder / f'README.{language}.md').write_bytes((template / f'README.{language}.md').read_bytes())
        (folder / 'PalSchema/raw').mkdir(parents=True)
        return info

    def test_reject_missing_targets_traversal_and_wrong_schema_nesting(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary)
            info = self.make_schema_package(folder)
            for target in ('../outside', 'C:/outside', './missing', './PalSchema/PointBlankBurstSkills'):
                info['InstallRule'][0]['Targets'] = [target]
                (folder / 'Info.json').write_text(json.dumps(info), encoding='utf-8')
                with self.subTest(target=target), self.assertRaises(ValueError):
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


if __name__ == '__main__':
    unittest.main()
