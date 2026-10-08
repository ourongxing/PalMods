"""Build PalMods locally through one entry point; never deploy to the game."""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys

from palmods import BUILD_ROOT, MODS_ROOT, PALCOMBO_BUILD, ROOT, UE4SS_BUILD
from build_sdk import ensure_sdk, toolset_environment

MODS = ('PalCombo', 'BetterWorkbench', 'UpdraftElevator', 'PointBlankBurstSkills')
SDK_MODS = {'PalCombo', 'BetterWorkbench'}


def positive_int(value):
    number = int(value)
    if number < 1:
        raise argparse.ArgumentTypeError('must be at least 1')
    return number


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mods', nargs='*', metavar='MOD',
                        help='Mods to build (default: all); SDK builds run first')
    parser.add_argument('--parallel', type=positive_int, default=4, help='CMake build workers (default: 4)')
    parser.add_argument('--toolset', help='CMake MSVC toolset, e.g. version=14.44.35207')
    parser.add_argument('--dry-run', action='store_true', help='Print steps without executing or writing files')
    parser.add_argument('--rebuild-sdk', action='store_true', help='Reconfigure and rebuild the shared SDK')
    args = parser.parse_args(argv)
    args.mods = args.mods or ['all']
    for mod in args.mods:
        if mod not in (*MODS, 'all', 'sdk'):
            parser.error(f'unknown mod {mod!r}; choose from {", ".join((*MODS, "all", "sdk"))}')
    return args


def commands_for(mod, args):
    toolset = args.toolset
    if not toolset and os.environ.get('VCToolsVersion'):
        toolset = 'version=' + os.environ['VCToolsVersion']
    tools = MODS_ROOT / mod / 'tools'

    def python_script(name, *options):
        return [sys.executable, str(tools / name), *options]

    if mod == 'PalCombo':
        configure = ['cmake', '-S', str(MODS_ROOT / mod / 'native'), '-B', str(PALCOMBO_BUILD),
                     '-G', 'Visual Studio 17 2022', '-A', 'x64', '-DPalModsSDK_DIR=' + str(UE4SS_BUILD)]
        if toolset:
            configure.extend(['-T', toolset])
        build = ['cmake', '--build', str(PALCOMBO_BUILD), '--config', 'Game__Shipping__Win64',
                 '--target', 'PalComboFillerNative', '--parallel', str(args.parallel)]
        version = re.search(r'(?:^|,)version=([^,]+)', toolset or '')
        if version:
            build.extend(['--', '/p:VCToolsVersion=' + version.group(1)])
        return [configure, build]
    if mod == 'BetterWorkbench':
        options = ['--enable-readonly', '--parallel', str(args.parallel)]
        if toolset:
            options.extend(['--toolset', toolset])
        return [python_script('build_native.py', *options), python_script('audit_native_imports.py')]
    if mod == 'UpdraftElevator':
        return [python_script('build_native.py'), python_script('run_native_build.py'),
                python_script('cook_native.py'), python_script('package_native.py', '--stage-only')]
    return []


def stage_schema():
    source = MODS_ROOT / 'PointBlankBurstSkills/mod'
    for path in source.rglob('*.json'):
        json.loads(path.read_text(encoding='utf-8-sig'))
    destination = BUILD_ROOT / 'PointBlankBurstSkills/stage/Mods/PalSchema/mods/PointBlankBurstSkills'
    # Replace only this generated mod directory so removed source files cannot linger.
    if not destination.resolve().is_relative_to(BUILD_ROOT.resolve()):
        raise ValueError(f'Stage path escapes build root: {destination}')
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination)
    return destination


def main(argv=None):
    args = parse_args(argv)
    selected = set(MODS if 'all' in args.mods else args.mods)
    artifacts = {
        'PalCombo': PALCOMBO_BUILD / 'Game__Shipping__Win64/bin/PalComboFillerNative.dll',
        'BetterWorkbench': BUILD_ROOT / 'BetterWorkbench/native/Release/BetterWorkbenchNative.dll',
        'UpdraftElevator': ROOT / 'dist/UpdraftElevator/UpdraftElevator-v9.zip',
        'PointBlankBurstSkills': BUILD_ROOT / 'PointBlankBurstSkills/stage/Mods/PalSchema/mods/PointBlankBurstSkills',
    }
    try:
        if 'sdk' in selected or selected & SDK_MODS:
            toolset = args.toolset or ('version=' + os.environ['VCToolsVersion']
                                      if os.environ.get('VCToolsVersion') else None)
            print(f'Preparing shared UE4SS SDK: {UE4SS_BUILD}', flush=True)
            if not args.dry_run:
                args.toolset = ensure_sdk(args.parallel, toolset, args.rebuild_sdk)
        for mod in MODS:
            if mod not in selected:
                continue
            print(f'\nBuilding {mod}', flush=True)
            for command in commands_for(mod, args):
                print(subprocess.list2cmdline(command), flush=True)
                if not args.dry_run:
                    env = toolset_environment(args.toolset) if mod in SDK_MODS else None
                    subprocess.run(command, cwd=ROOT, env=env, check=True)
            if mod == 'PointBlankBurstSkills':
                print('Validate JSON and stage PalSchema files', flush=True)
                if not args.dry_run:
                    stage_schema()
            if not args.dry_run and not artifacts[mod].exists():
                raise FileNotFoundError(f'Build did not produce expected artifact: {artifacts[mod]}')
            print(f'{"Planned output" if args.dry_run else "Built"}: {artifacts[mod]}', flush=True)
    except (subprocess.CalledProcessError, OSError, ValueError) as error:
        print(f'Build failed: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
