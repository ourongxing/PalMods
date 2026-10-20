"""Run the compiled reward regression through the shared native test build."""
from pathlib import Path
import subprocess
import runpy
ROOT = Path(__file__).resolve().parents[3]
runpy.run_path(str(Path(__file__).parent / 'check_ui.py'))
BUILD = ROOT / '.build/tests'
subprocess.run(['cmake', '-S', str(ROOT), '-B', str(BUILD)], check=True)
subprocess.run(['cmake', '--build', str(BUILD), '--config', 'Release', '--target', 'better_expedition_rewards'], check=True)
subprocess.run(['ctest', '--test-dir', str(BUILD), '-C', 'Release', '-R', '^better_expedition_rewards$', '--output-on-failure'], check=True)
