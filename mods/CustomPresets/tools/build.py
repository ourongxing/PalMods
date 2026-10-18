"""Build the local development package without installing it."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import sys
from zipfile import ZipFile, ZIP_DEFLATED

MOD = Path(__file__).resolve().parents[1]
ROOT = MOD.parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from build_sdk import ensure_sdk, toolset_environment
from palmods import UE4SS_ROOT
import pefile
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
bridge = pefile.PE(str(dll))
runtime_path = UE4SS_ROOT / 'UE4SS.dll'
runtime = pefile.PE(str(runtime_path))
exports = {symbol.name for symbol in runtime.DIRECTORY_ENTRY_EXPORT.symbols if symbol.name}
imports = {symbol.name for entry in bridge.DIRECTORY_ENTRY_IMPORT if entry.dll.lower() == b'ue4ss.dll'
           for symbol in entry.imports}
if not imports or imports - exports:
    raise SystemExit(f'UE4SS import audit failed: {imports - exports}')
(ROOT / '.build/CustomPresets/import-audit.json').write_text(json.dumps({
    'dll_sha256': hashlib.sha256(dll.read_bytes()).hexdigest(),
    'runtime_sha256': hashlib.sha256(runtime_path.read_bytes()).hexdigest(),
    'imports_verified': len(imports),
}, indent=2) + '\n', encoding='utf-8')
output = ROOT / 'dist/CustomPresets/CustomPresets-1.0.0.zip'
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
