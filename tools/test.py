"""Run existing offline regressions across all three mods; never install to game."""
from pathlib import Path
import argparse
import subprocess
import sys
from palmods import ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-native', action='store_true', help='Only run Lua/schema regressions')
    args = parser.parse_args()
    scripts = [ROOT / 'mods/BetterWorkbench/tests/run.py']
    scripts.append(ROOT / 'mods/BetterBulkStorage/tests/run.py')
    scripts.append(ROOT / 'mods/AnywherePalBox/tests/run.py')
    scripts.extend(ROOT / 'mods/UpdraftElevator/tests' / name for name in (
        'check_native_cost.py', 'check_native_jump.py', 'check_native_config.py',
        'check_native_package.py', 'check_native_category.py'))
    for script in scripts:
        print(f'Running {script.relative_to(ROOT)}', flush=True)
        subprocess.run([sys.executable, str(script)], cwd=ROOT, check=True)
    if not args.skip_native:
        build = ROOT / '.build/tests'
        subprocess.run(['cmake', '-S', str(ROOT), '-B', str(build)], check=True)
        subprocess.run(['cmake', '--build', str(build), '--config', 'Release', '--parallel'], check=True)
        subprocess.run(['ctest', '--test-dir', str(build), '-C', 'Release', '--output-on-failure'], check=True)


if __name__ == '__main__':
    main()
