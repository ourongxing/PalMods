"""Check the real cooked continuation patch and its preserved execution stack."""
from pathlib import Path
import importlib.util
import json
import struct
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from palmods import REPAK, GAME_ROOT
import subprocess
import tempfile

spec = importlib.util.spec_from_file_location('quickbutcher_build', Path(__file__).resolve().parents[1] / 'tools/build.py')
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)

with tempfile.TemporaryDirectory() as temporary:
    folder = Path(temporary)
    subprocess.run([str(REPAK), 'unpack', str(GAME_ROOT / 'Pal/Content/Paks/Pal-Windows.pak'),
                    '-o', str(folder), '-i', build.ASSET + '.uexp'], check=True)
    data = (folder / (build.ASSET + '.uexp')).read_bytes()
    patched = build.patch_export(data)
    assert len(patched) == len(data)
    assert [i for i, (a, b) in enumerate(zip(data, patched)) if a != b] == [build.PATCH_OFFSET, build.PATCH_OFFSET + 1]
    assert data[:build.PATCH_OFFSET] == patched[:build.PATCH_OFFSET]
    assert data[build.PATCH_OFFSET + 4:] == patched[build.PATCH_OFFSET + 4:]
    # Decode the actual three EX_PushExecutionFlow instructions, in LIFO order.
    stack = []
    for offset in range(build.FLOW_START, build.FLOW_START + 15, 5):
        assert patched[offset] == 0x4c
        stack.append(struct.unpack_from('<I', patched, offset + 1)[0])
    assert [stack.pop(), stack.pop(), stack.pop()] == [1406, 2481, 2501]
    # Original completion branch sets both flags, then pops to the remaining setup.
    completion = data[build.BYTECODE_START + 2042:build.BYTECODE_START + 2081]
    assert completion.hex() == '1401010000000200000000000000e7ffffff271401010000004e0000000000000001000000274d'
    assert patched[build.BYTECODE_START + 2042:build.BYTECODE_START + 2081] == completion
    # Invalid-target branch stays intact: end without requesting Pal deletion.
    assert data[build.BYTECODE_START + 2601:build.BYTECODE_START + 2640] == patched[build.BYTECODE_START + 2601:build.BYTECODE_START + 2640]
    for invalid in (data[:-1], data[:100] + bytes([data[100] ^ 1]) + data[101:], patched):
        try:
            build.patch_export(invalid)
        except ValueError:
            pass
        else:
            raise AssertionError('An altered or already-patched source was accepted')

audit = ROOT / 'dist/QuickButcher/build-audit.json'
if audit.exists():
    report = json.loads(audit.read_text(encoding='utf-8'))
    assert report['Files']['BP_ActionCutPalMeat_Player.uasset']['ChangedOffsets'] == []
    assert report['Files']['BP_ActionCutPalMeat_Player.uexp']['ChangedOffsets'] == [build.PATCH_OFFSET, build.PATCH_OFFSET + 1]
    assert build.digest((audit.parent / 'QuickButcher_P.pak').read_bytes()) == report['PakSHA256']
server_pak = build.SERVER_ROOT / 'Pal/Content/Paks/Pal-WindowsServer.pak'
if server_pak.exists():
    with tempfile.TemporaryDirectory() as temporary:
        folder = Path(temporary)
        subprocess.run([str(REPAK), 'unpack', str(server_pak), '-o', str(folder),
                        '-i', build.ASSET + '.uexp', '-i', build.ASSET + '.uasset'], check=True)
        source = (folder / (build.ASSET + '.uexp')).read_bytes()
        assert build.digest((folder / (build.ASSET + '.uasset')).read_bytes()) == build.SERVER_HASHES['.uasset']
        patched = build.patch_export(source, server=True)
        shift = build.SERVER_BYTECODE_START - build.BYTECODE_START
        patch_offset = build.PATCH_OFFSET + shift
        assert [i for i, (a, b) in enumerate(zip(source, patched)) if a != b] == [patch_offset, patch_offset + 1]
        stack = [struct.unpack_from('<I', patched, offset + 1)[0]
                 for offset in range(build.FLOW_START + shift, build.FLOW_START + shift + 15, 5)]
        assert list(reversed(stack)) == [1406, 2481, 2501]
        completion = source[build.SERVER_BYTECODE_START + 2042:build.SERVER_BYTECODE_START + 2081]
        assert completion.hex() == '1401010000000200000000000000e7ffffff271401010000004e0000000000000001000000274d'
        for bad in (source[:-1], source[:100] + bytes([source[100] ^ 1]) + source[101:], patched, data):
            try:
                build.patch_export(bad, server=True)
            except ValueError:
                pass
            else:
                raise AssertionError('Server patch accepted altered/client/already-patched asset')
    server_audit = ROOT / 'dist/QuickButcher/server/build-audit.json'
    if server_audit.exists():
        report = json.loads(server_audit.read_text(encoding='utf-8'))
        assert report['Target'] == 'server'
        assert report['Files']['BP_ActionCutPalMeat_Player.uasset']['ChangedOffsets'] == []
        assert report['Files']['BP_ActionCutPalMeat_Player.uexp']['ChangedOffsets'] == [patch_offset, patch_offset + 1]
        assert build.digest((server_audit.parent / 'QuickButcher_P.pak').read_bytes()) == report['PakSHA256']
    print('PASS: dedicated-server cooked variant, completion flags, continuation order and client-asset rejection')
print('PASS: guarded cooked patch, completion flags, setup order, invalid-target branch, unchanged settlement bytes and artifact hashes')
