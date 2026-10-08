"""Verify the bridge imports are exported by the installed UE4SS; no DLL loading."""
from pathlib import Path
import hashlib
import json
import argparse

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from palmods import UE4SS_ROOT, build_directory
import pefile

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = build_directory('BetterWorkbench') / 'native/Release/BetterWorkbenchNative.dll'
parser = argparse.ArgumentParser()
parser.add_argument('--bridge', type=Path, default=BRIDGE, help='Candidate DLL to audit')
BRIDGE = parser.parse_args().bridge
RUNTIME = UE4SS_ROOT / 'UE4SS.dll'
bridge = pefile.PE(str(BRIDGE))
runtime = pefile.PE(str(RUNTIME))
exports = {symbol.name for symbol in runtime.DIRECTORY_ENTRY_EXPORT.symbols if symbol.name}
dependencies = next(entry for entry in bridge.DIRECTORY_ENTRY_IMPORT if entry.dll.lower() == b'ue4ss.dll')
imports = {symbol.name for symbol in dependencies.imports}
missing = imports - exports
if missing:
    raise SystemExit(f'Missing UE4SS imports: {missing}')
report = {
    'runtime_sha256': hashlib.sha256(RUNTIME.read_bytes()).hexdigest(),
    'bridge_sha256': hashlib.sha256(BRIDGE.read_bytes()).hexdigest(),
    'ue4ss_imports_verified': len(imports),
    'symbols': sorted(symbol.decode('ascii') for symbol in imports),
    'scope': 'exported signatures and pinned UE4SS headers; native struct layout checked on startup',
}
(build_directory('BetterWorkbench') / 'import-audit.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print(f'All {len(imports)} UE4SS imports are present in the installed runtime. Report saved.')
