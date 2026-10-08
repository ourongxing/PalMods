from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import build_sdk


class SharedSDKTests(unittest.TestCase):
    def fixture(self, directory):
        root = Path(directory).resolve()
        source = root / 'source'
        (source / 'UE4SS/include').mkdir(parents=True)
        cache = root / 'cache'
        cache.mkdir()
        (cache / 'UE4SS.lib').write_bytes(b'fixture')
        project = cache / 'consumer.vcxproj'
        project.write_text('''<Project xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
<ItemDefinitionGroup Condition="'$(Configuration)|$(Platform)'=='Game__Shipping__Win64|x64'">
<ClCompile><AdditionalIncludeDirectories>C:/old/RE-UE4SS/UE4SS/include;C:/old/private;%(AdditionalIncludeDirectories)</AdditionalIncludeDirectories>
<PreprocessorDefinitions>UE_GAME;Consumer_EXPORTS;CMAKE_INTDIR="Shipping";%(PreprocessorDefinitions)</PreprocessorDefinitions></ClCompile>
<Link><AdditionalDependencies>C:/old/build/UE4SS.lib;kernel32.lib;%(AdditionalDependencies)</AdditionalDependencies></Link>
</ItemDefinitionGroup></Project>''', encoding='utf-8')
        destination = root / 'sdk'
        return source, cache, project, destination

    def test_legacy_import_exports_only_shared_requirements(self):
        with tempfile.TemporaryDirectory() as directory:
            source, cache, project, destination = self.fixture(directory)
            build_sdk.export_package(project, cache, source, destination, 'C:/old', 'version=14.44.35207')
            config = (destination / 'PalModsSDKConfig.cmake').read_text()
            self.assertIn('PalMods::UE4SS', config)
            self.assertIn((cache / 'UE4SS.lib').as_posix(), config)
            self.assertNotIn('Consumer_EXPORTS', config)
            self.assertNotIn('CMAKE_INTDIR', config)
            self.assertNotIn('C:/old', config)
            self.assertNotIn('private', config)
            project.unlink()  # Daily builds must not need the original consumer project.
            with patch.object(build_sdk, 'UE4SS_BUILD', destination), patch.object(build_sdk, 'UE4SS_SOURCE', source):
                with patch.object(build_sdk.subprocess, 'run') as run:
                    self.assertEqual(build_sdk.ensure_sdk(toolset='version=14.44.35207'), 'version=14.44.35207')
                    run.assert_not_called()
                with self.assertRaises(ValueError):
                    build_sdk.ensure_sdk(toolset='version=99.0')
                (cache / 'UE4SS.lib').unlink()
                with self.assertRaises(FileNotFoundError):
                    build_sdk.ensure_sdk()

    def test_incomplete_import_does_not_publish_package(self):
        with tempfile.TemporaryDirectory() as directory:
            source, cache, project, destination = self.fixture(directory)
            (cache / 'UE4SS.lib').unlink()
            with self.assertRaises(FileNotFoundError):
                build_sdk.export_package(project, cache, source, destination, 'C:/old')
            self.assertFalse(destination.exists())

    def test_new_sdk_build_uses_neutral_consumer(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory).resolve() / 'sdk'
            with patch.object(build_sdk, 'UE4SS_BUILD', destination):
                with patch.object(build_sdk.subprocess, 'run') as run, patch.object(build_sdk, 'export_package') as export:
                    build_sdk.ensure_sdk(parallel=2, toolset='version=14.44.35207')
            self.assertEqual(run.call_count, 2)
            configure, compile_command = [call.args[0] for call in run.call_args_list]
            self.assertIn(str(build_sdk.ROOT / 'tools/sdk'), configure)
            self.assertIn('PalModsSDKProbe', compile_command)
            self.assertIn('/p:VCToolsVersion=14.44.35207', compile_command)
            for call in run.call_args_list:
                self.assertEqual(call.kwargs['env']['VCToolsVersion'], '14.44.35207')
            self.assertNotIn('PalCombo', ' '.join(configure + compile_command))
            self.assertEqual(export.call_args.args[0], destination / 'PalModsSDKProbe.vcxproj')


if __name__ == '__main__':
    unittest.main()
