"""Build orchestration coverage without compilers or game writes."""
import contextlib
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import build


class BuildTests(unittest.TestCase):
    def test_default_dry_run_never_executes_or_stages(self):
        with patch.object(build.subprocess, 'run') as run, patch.object(build, 'stage_schema') as stage, patch.object(build, 'ensure_sdk') as sdk:
            with contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(build.main(['--dry-run']), 0)
        run.assert_not_called()
        stage.assert_not_called()
        sdk.assert_not_called()
        text = output.getvalue()
        positions = [text.index('Building ' + mod) for mod in build.MODS]
        self.assertEqual(positions, sorted(positions))
        self.assertIn('--stage-only', text)
        self.assertIn('--enable-readonly', text)

    def test_selected_mods_keep_dependency_order_and_deduplicate(self):
        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(build.main(['BetterWorkbench', 'PalCombo', 'PalCombo', '--dry-run']), 0)
        text = output.getvalue()
        self.assertLess(text.index('Building PalCombo'), text.index('Building BetterWorkbench'))
        self.assertEqual(text.count('Building PalCombo'), 1)
        self.assertNotIn('Building UpdraftElevator', text)

    def test_failure_stops_before_dependent_build(self):
        with patch.object(build, 'ensure_sdk', side_effect=subprocess.CalledProcessError(7, 'cmake')) as sdk, patch.object(build.subprocess, 'run') as run:
            with patch.object(build, 'stage_schema') as stage:
                with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                    self.assertEqual(build.main(['all']), 1)
        sdk.assert_called_once()
        run.assert_not_called()
        stage.assert_not_called()

    def test_toolset_and_parallel_reach_both_native_builds(self):
        args = build.parse_args(['--parallel', '2', '--toolset', 'version=14.44.35207'])
        combo = build.commands_for('PalCombo', args)
        workbench = build.commands_for('BetterWorkbench', args)
        self.assertIn('version=14.44.35207', combo[0])
        self.assertIn('/p:VCToolsVersion=14.44.35207', combo[1])
        self.assertEqual(combo[1][combo[1].index('--parallel') + 1], '2')
        self.assertIn('version=14.44.35207', workbench[0])
        self.assertEqual(workbench[0][workbench[0].index('--parallel') + 1], '2')
        with patch.dict(build.os.environ, {'VCToolsVersion': '14.44.35207'}):
            inherited = build.commands_for('PalCombo', build.parse_args([]))
        self.assertIn('/p:VCToolsVersion=14.44.35207', inherited[1])

    def test_successful_command_without_artifact_is_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            with patch.object(build, 'PALCOMBO_BUILD', Path(temporary) / 'missing'):
                with patch.object(build.subprocess, 'run'), patch.object(build, 'ensure_sdk', return_value=None):
                    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                        self.assertEqual(build.main(['PalCombo']), 1)

    def test_workbench_only_prepares_sdk_without_building_palcombo(self):
        with patch.object(build, 'ensure_sdk', return_value='version=14.44.35207') as sdk:
            with patch.object(build.subprocess, 'run') as run, patch.object(Path, 'exists', return_value=True):
                with contextlib.redirect_stdout(io.StringIO()):
                    self.assertEqual(build.main(['BetterWorkbench']), 0)
        sdk.assert_called_once()
        self.assertEqual(run.call_count, 2)
        for call in run.call_args_list:
            self.assertNotIn('PalCombo', ' '.join(call.args[0]))
        self.assertIn('version=14.44.35207', run.call_args_list[0].args[0])

    def test_invalid_selection_and_parallel_rejected(self):
        for argv in (['MissingMod'], ['--parallel', '0'], ['--parallel', '-1']):
            with self.subTest(argv=argv), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit):
                    build.parse_args(argv)

    def test_schema_staging_removes_obsolete_files_and_rejects_bad_json(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'mods/CloseRangeBurstSkills/mod/raw'
            source.mkdir(parents=True)
            data = source / 'skills.json'
            data.write_text('{"skills": []}', encoding='utf-8')
            with patch.object(build, 'MODS_ROOT', root / 'mods'), patch.object(build, 'BUILD_ROOT', root / 'build'):
                destination = build.stage_schema()
                self.assertEqual((destination / 'raw/skills.json').read_bytes(), data.read_bytes())
                (destination / 'obsolete.txt').write_text('old', encoding='utf-8')
                build.stage_schema()
                self.assertFalse((destination / 'obsolete.txt').exists())
                data.write_text('{invalid', encoding='utf-8')
                with self.assertRaises(ValueError):
                    build.stage_schema()
                self.assertEqual((destination / 'raw/skills.json').read_text(), '{"skills": []}')


if __name__ == '__main__':
    unittest.main()
