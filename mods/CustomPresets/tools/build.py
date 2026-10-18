"""Build the local development package without installing it."""
from pathlib import Path
import argparse
import subprocess
import sys
from zipfile import ZipFile, ZIP_DEFLATED

MOD = Path(__file__).resolve().parents[1]
ROOT = MOD.parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from build_sdk import ensure_sdk, toolset_environment
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--parallel', type=int, default=4)
parser.add_argument('--toolset')
args = parser.parse_args()
toolset = ensure_sdk(args.parallel, args.toolset)
env = toolset_environment(toolset)
build = ROOT / '.build/CustomPresets/native-ascii'
subprocess.run(['cmake', '-S', str(MOD / 'native'), '-B', str(build), '-G', 'Visual Studio 17 2022',
                '-A', 'x64', '-T', toolset], env=env, check=True)
subprocess.run(['cmake', '--build', str(build), '--config', 'Game__Shipping__Win64',
                '--parallel', str(args.parallel), '--', '/p:VCToolsVersion=' + toolset.split('=', 1)[1]], env=env, check=True)
dll = build / 'Game__Shipping__Win64/bin/CustomPresetsNative.dll'
output = ROOT / 'dist/CustomPresets/CustomPresets-0.4.6.zip'
output.parent.mkdir(parents=True, exist_ok=True)
with ZipFile(output, 'w', ZIP_DEFLATED) as archive:
    for path in sorted((MOD / 'mod').rglob('*')):
        if path.parent == MOD / 'mod/presets' and path.name != 'KEEP.txt':
            continue
        if path.is_file() and path.suffix not in ('.preset', '.bak', '.tmp', '.deleted'):
            archive.write(path, 'CustomPresets/' + path.relative_to(MOD / 'mod').as_posix())
    archive.write(MOD / 'README.md', 'CustomPresets/README.md')
    archive.write(dll, 'CustomPresets/dlls/main.dll')
print(output)
