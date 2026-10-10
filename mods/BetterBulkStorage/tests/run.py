"""Audit supported game calls and exercise the incremental preview scheduler."""
from pathlib import Path
import sys
import subprocess
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from palmods import GAME_EXE, UE4SS_ROOT, load_lua_runtime
from audit_interfaces import audit
sys.path.insert(0, str(ROOT / 'mods/BetterBulkStorage/tools'))
from build import generate_guard
scripts=ROOT/'mods/BetterBulkStorage/mod/Scripts'
source='\n'.join(p.read_text(encoding='utf-8') for p in scripts.rglob('*.lua'))
audit(source, UE4SS_ROOT/'UE4SS_ObjectDump.txt')
try:
    audit(source.replace('FindConcreteModel(d.guid(info.OwnerMapObjectConcreteModelInstanceId))', 'FindConcreteModel()'), UE4SS_ROOT/'UE4SS_ObjectDump.txt')
except AssertionError as error:
    assert 'FindConcreteModel: expected 1 arguments, found 0' in str(error)
else:
    raise AssertionError('Missing-argument regression was not detected')
if GAME_EXE.exists(): generate_guard()
lua=load_lua_runtime()(unpack_returned_tuples=True)
for p in scripts.rglob('*.lua'): lua.execute('assert(load(...))',p.read_text(encoding='utf-8'))
lua.globals().SCRIPTS=str(scripts).replace('\\','/')
lua.execute((Path(__file__).parent/'preview.lua').read_text(encoding='utf-8'))
# Exercise the exact C++ helper used by the DLL, with fake game memory and
# a rejecting authoritative transfer callback, rather than a Python replica.
from build_sdk import toolset_environment
native_test = ROOT/'.build/BetterBulkStorage/tests'
native_test.mkdir(parents=True, exist_ok=True)
subprocess.run(['cmake', '-S', str(Path(__file__).parent), '-B', str(native_test),
    '-G', 'Visual Studio 17 2022', '-A', 'x64', '-T', 'version=14.44.35207'],
    env=toolset_environment('version=14.44.35207'), check=True)
subprocess.run(['cmake', '--build', str(native_test), '--config', 'Release',
    '--', '/p:VCToolsVersion=14.44.35207'], check=True)
subprocess.run([str(native_test/'Release/storage_transfer.exe')], check=True)
print('PASS: supported interfaces/binary guards, key-only bounded preview, cancellation, deduplication, filters, locks, eggs, exclusions and base transitions')
