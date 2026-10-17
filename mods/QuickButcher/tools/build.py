"""Build a guarded animation-skip patch from local game assets; never install."""
from pathlib import Path
import hashlib
import json
import shutil
import struct
import subprocess
import sys
import tempfile
from zipfile import ZipFile, ZIP_DEFLATED

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from palmods import GAME_ROOT, REPAK, build_directory, DIST_ROOT

MOD = Path(__file__).resolve().parents[1]
ASSET = 'Pal/Content/Pal/Blueprint/Action/Palmi/BP_ActionCutPalMeat_Player'
HASHES = {
    '.uasset': 'c250d013d5d6cf4fa02a221509448e2c95cabd562cc93388e03ed1d3959d7301',
    '.uexp': '5d8b61115519f9139eb2f95b380a0e3af92fbb0d63932aeda5e57dfe8a09bd40',
}
BYTECODE_START = 4305
FLOW_START = BYTECODE_START + 2263
PATCH_OFFSET = FLOW_START + 11
MONTAGE_ENTRY, COMPLETION_ENTRY = 1836, 1406
ORIGINAL_FLOW = b''.join(b'\x4c' + struct.pack('<I', entry) for entry in (2501, 2481, MONTAGE_ENTRY))


def digest(data):
    return hashlib.sha256(data).hexdigest()


def patch_export(data):
    if digest(data) != HASHES['.uexp']:
        raise ValueError('Unsupported game action asset; re-analyze before building QuickButcher')
    if data[FLOW_START:FLOW_START + 15] != ORIGINAL_FLOW:
        raise ValueError('Unexpected OnBeginAction execution stack')
    # Replace only the third continuation: after target setup, use the original
    # successful completion flags instead of the montage/proxy/delegate block.
    # Earlier continuations still disable input and start the server target action;
    # native action ticking then invokes the unchanged OnEndAction cleanup/rewards.
    result = data[:PATCH_OFFSET] + struct.pack('<I', COMPLETION_ENTRY) + data[PATCH_OFFSET + 4:]
    if len(result) != len(data) or result[:PATCH_OFFSET] != data[:PATCH_OFFSET] or result[PATCH_OFFSET + 4:] != data[PATCH_OFFSET + 4:]:
        raise ValueError('Patch changed bytes outside the continuation address')
    return result


def build():
    build_root = build_directory('QuickButcher')
    output = DIST_ROOT / 'QuickButcher'
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='build-', dir=build_root) as temporary:
        work = Path(temporary)
        original, patched = work / 'original', work / 'patched'
        original.mkdir()
        command = [str(REPAK), 'unpack', str(GAME_ROOT / 'Pal/Content/Paks/Pal-Windows.pak'),
                   '-o', str(original)]
        for extension in HASHES:
            command += ['-i', ASSET + extension]
        subprocess.run(command, check=True)
        audit = {'Mod': 'QuickButcher', 'Version': '1.0.0',
                 'GameTest': 'Pending in-game verification', 'Files': {}}
        for extension, expected in HASHES.items():
            source = original / (ASSET + extension)
            data = source.read_bytes()
            if digest(data) != expected:
                raise ValueError(f'Unsupported source asset: {source.name}')
            modified = patch_export(data) if extension == '.uexp' else data
            destination = patched / (ASSET + extension)
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(modified)
            audit['Files'][source.name] = {'SourceSHA256': digest(data), 'PatchedSHA256': digest(modified),
                                         'ChangedOffsets': [i for i, (a, b) in enumerate(zip(data, modified)) if a != b]}
        pak = work / 'QuickButcher_P.pak'
        subprocess.run([str(REPAK), 'pack', '--version', 'V11', '--compression', 'Zlib',
                        str(patched), str(pak)], check=True)
        entries = subprocess.check_output([str(REPAK), 'list', str(pak)], text=True).splitlines()
        if set(entries) != {ASSET + extension for extension in HASHES}:
            raise ValueError('Unexpected PAK contents')
        # Check bytes after packing/unpacking, not only the staging tree.
        verified = work / 'verified'
        verified.mkdir()
        subprocess.run([str(REPAK), 'unpack', str(pak), '-o', str(verified)], check=True)
        for extension in HASHES:
            relative = ASSET + extension
            if (verified / relative).read_bytes() != (patched / relative).read_bytes():
                raise ValueError(f'PAK round-trip mismatch: {relative}')
        audit['PakSHA256'] = digest(pak.read_bytes())
        audit['Continuation'] = {'From': MONTAGE_ENTRY, 'To': COMPLETION_ENTRY, 'FileOffset': PATCH_OFFSET}
        shutil.copy2(pak, output / pak.name)
        (output / 'build-audit.json').write_text(json.dumps(audit, indent=2) + '\n', encoding='utf-8')
        with ZipFile(output / 'QuickButcher-1.0.0.zip', 'w', ZIP_DEFLATED) as archive:
            archive.write(pak, 'Pal/Content/Paks/~mods/QuickButcher/' + pak.name)
            archive.write(MOD / 'README.md', 'QuickButcher-README.md')
    print(output / 'QuickButcher-1.0.0.zip')


if __name__ == '__main__':
    build()
