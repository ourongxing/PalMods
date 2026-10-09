"""Build and package the experimental native/Lua storage enhancement. Never install."""
from pathlib import Path
import hashlib
import argparse
import json
import shutil
import subprocess
import sys
import zipfile
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from palmods import GAME_EXE, load_lua_runtime
from build_sdk import toolset_environment
import pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

MOD = ROOT / 'mods/EnhancedBulkStorage'
BUILD = ROOT / '.build/EnhancedBulkStorage/native'
EXPECTED_HASH = 'e590b5e7bfaa3fea40fab1a02cc72c8fc5fd6f8631ef2308e95ac56c25195837'
FUNCTION_RVA, FUNCTION_END = 0x2da9a60, 0x2da9cb9
PATCH_RVA, CALL_RVA = 0x2da9bcd, 0x2dbd9d6

def generate_guard():
    digest = hashlib.sha256(GAME_EXE.read_bytes()).hexdigest()
    if digest != EXPECTED_HASH:
        raise SystemExit('Unsupported game binary; re-analyze storage before building')
    pe = pefile.PE(str(GAME_EXE), fast_load=True)
    code = pe.get_data(FUNCTION_RVA, FUNCTION_END - FUNCTION_RVA)
    instructions = {i.address: i for i in Cs(CS_ARCH_X86, CS_MODE_64).disasm(code, FUNCTION_RVA)}
    patch = instructions[PATCH_RVA]
    assert patch.mnemonic == 'je' and patch.op_str == '0x2da9c78' and patch.size == 6
    assert instructions[PATCH_RVA - 3].mnemonic == 'test' and instructions[PATCH_RVA - 3].op_str == 'r13b, r13b'
    assert len([i for i in instructions.values() if i.mnemonic == 'call' and i.op_str == '0x2fbc1f0']) == 2
    call = pe.get_data(CALL_RVA, 5)
    decoded = next(Cs(CS_ARCH_X86, CS_MODE_64).disasm(call, CALL_RVA))
    assert decoded.mnemonic == 'call' and decoded.op_str == hex(FUNCTION_RVA)
    def array(name, value):
        return f'inline constexpr std::array<std::uint8_t, {len(value)}> {name}{{' + ','.join(f'0x{x:02x}' for x in value) + '};\n'
    generated = BUILD / 'generated'
    generated.mkdir(parents=True, exist_ok=True)
    header = '#pragma once\n#include <array>\n#include <cstdint>\nnamespace guard {\n'
    for name, value in [('function_rva', FUNCTION_RVA), ('patch_rva', PATCH_RVA), ('call_rva', CALL_RVA),
                        ('timestamp', pe.FILE_HEADER.TimeDateStamp), ('image_size', pe.OPTIONAL_HEADER.SizeOfImage)]:
        header += f'inline constexpr std::uint32_t {name} = 0x{value:x};\n'
    header += array('function', code) + array('original', bytes(patch.bytes)) + array('call', call) + '}\n'
    (generated / 'binary_guard.hpp').write_text(header, encoding='utf-8')
    (BUILD / 'analysis.json').write_text(json.dumps({'game_sha256': digest, 'function_rva': hex(FUNCTION_RVA),
        'patch_rva': hex(PATCH_RVA), 'original': bytes(patch.bytes).hex(), 'call_rva': hex(CALL_RVA)}, indent=2))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--toolset', default='version=14.44.35207')
    parser.add_argument('--parallel', type=int, default=4)
    args = parser.parse_args()
    generate_guard()
    lua = load_lua_runtime()()
    lua.execute('assert(load(...))', (MOD / 'mod/Scripts/main.lua').read_text(encoding='utf-8'))
    env = toolset_environment(args.toolset)
    subprocess.run(['cmake', '-S', str(MOD / 'native'), '-B', str(BUILD), '-G', 'Visual Studio 17 2022', '-A', 'x64', '-T', args.toolset], env=env, check=True)
    command = ['cmake', '--build', str(BUILD), '--config', 'Game__Shipping__Win64', '--parallel', str(args.parallel)]
    if args.toolset.startswith('version='):
        command += ['--', '/p:VCToolsVersion=' + args.toolset.split('=', 1)[1]]
    subprocess.run(command, env=env, check=True)
    output = ROOT / 'dist/EnhancedBulkStorage'
    stage = output / 'EnhancedBulkStorage'
    shutil.copytree(MOD / 'mod', stage, dirs_exist_ok=True)
    (stage / 'dlls').mkdir(exist_ok=True)
    shutil.copy2(BUILD / 'Game__Shipping__Win64/bin/EnhancedBulkStorageNative.dll', stage / 'dlls/main.dll')
    dll = pefile.PE(str(stage / 'dlls/main.dll'))
    exports = {entry.name for entry in dll.DIRECTORY_ENTRY_EXPORT.symbols}
    assert {b'start_mod', b'uninstall_mod', b'luaopen_EnhancedBulkStorage'} <= exports
    shutil.copy2(MOD / 'README.md', stage / 'README.md')
    with zipfile.ZipFile(output / 'EnhancedBulkStorage-0.1.0-experimental.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(stage.rglob('*')):
            if path.is_file(): archive.write(path, path.relative_to(output))
    print(output / 'EnhancedBulkStorage-0.1.0-experimental.zip')

if __name__ == '__main__': main()
