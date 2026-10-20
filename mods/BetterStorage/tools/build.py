"""Build and package Better Storage with vanilla quick-storage rules. Never install."""
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

MOD = ROOT / 'mods/BetterStorage'
BUILD = ROOT / '.build/BetterStorage/native'
EXPECTED_HASH = 'e590b5e7bfaa3fea40fab1a02cc72c8fc5fd6f8631ef2308e95ac56c25195837'
# Read the shared None FName from this verified RIP-relative reference.
NONE_REFERENCE_RVA = 0x2da9b11
PERMISSION_RVA, PERMISSION_END = 0x2fb1750, 0x2fb17ec
FILTER_RVA, FILTER_END = 0x2faf900, 0x2fafb89
MAXIMUM_RVA = 0x2fad5a0
TRANSPORT_RVA, TRANSPORT_END = 0x2d7b690, 0x2d7c1e5
TRANSPORT_PATCH_RVA = 0x2d7c0e0
# Native implementations behind the two reflected container accessors.
MODULE_RVA, MODULE_END = 0x2fff160, 0x2fff212
CONTAINER_RVA, CONTAINER_END = 0x3067b70, 0x3067b92
STATIC_DATA_RVA = 0x2fadd10
STACK_LOOKUP_RVA, STACK_LOOKUP_END = 0x32651f0, 0x32652b4
VALIDATION_RVA, FULL_TEST_RVA, FULL_TEST2_RVA, PRODUCTION_RVA = 0x2fc07a0, 0x2fb12f0, 0x2fb0b90, 0x30ba0f0
DEDICATED_SERVER = False

def configure_server():
    globals().update({
        'DEDICATED_SERVER': True,
        'GAME_EXE': Path(r'G:\PalworldTestServer\Pal\Binaries\Win64\PalServer-Win64-Shipping-Cmd.exe'),
        'BUILD': ROOT / '.build/BetterStorage/server-native',
        'EXPECTED_HASH': '6f929673e7ac637d591d6f3454dbd396be7911093311cb8b24af3a152b217f49',
        'NONE_REFERENCE_RVA': 0x2c544f1,
        'PERMISSION_RVA': 0x2e5c4d0, 'PERMISSION_END': 0x2e5c56c,
        'FILTER_RVA': 0x2e5a680, 'FILTER_END': 0x2e5a909,
        'MAXIMUM_RVA': 0x2e58320,
        'TRANSPORT_RVA': 0x2c26070, 'TRANSPORT_END': 0x2c26bc5,
        'TRANSPORT_PATCH_RVA': 0x2c26ac0,
        'MODULE_RVA': 0x2ea97d0, 'MODULE_END': 0x2ea9882,
        'CONTAINER_RVA': 0x2f12350, 'CONTAINER_END': 0x2f12372,
        'STATIC_DATA_RVA': 0x2e58a90,
        'STACK_LOOKUP_RVA': 0x310fd40, 'STACK_LOOKUP_END': 0x310fe04,
        'VALIDATION_RVA': 0x2e6b520, 'FULL_TEST_RVA': 0x2e5c070,
        'FULL_TEST2_RVA': 0x2e5b910, 'PRODUCTION_RVA': 0x2f648c0,
    })

def generate_guard():
    digest = hashlib.sha256(GAME_EXE.read_bytes()).hexdigest()
    if digest != EXPECTED_HASH:
        raise SystemExit('Unsupported game binary; re-analyze storage before building')
    pe = pefile.PE(str(GAME_EXE), fast_load=True)
    decoder = Cs(CS_ARCH_X86, CS_MODE_64)
    decoder.detail = True
    none_reference = next(decoder.disasm(pe.get_data(NONE_REFERENCE_RVA, 15), NONE_REFERENCE_RVA))
    none_rva = none_reference.address + none_reference.size + none_reference.operands[1].mem.disp
    transport = pe.get_data(TRANSPORT_RVA, TRANSPORT_END - TRANSPORT_RVA)
    ranking = list(decoder.disasm(pe.get_data(TRANSPORT_PATCH_RVA, 14), TRANSPORT_PATCH_RVA))
    assert [(i.mnemonic, i.op_str) for i in ranking] == [
        ('mov', 'rax, qword ptr [rbx + 8]'), ('movzx', 'ecx, byte ptr [rax]'),
        ('movd', 'xmm7, ecx'), ('cvtdq2ps', 'xmm7, xmm7')]
    assert sum(i.size for i in ranking) == 14
    # Transfer validation uses these predicates with the same container offsets.
    validation = list(Cs(CS_ARCH_X86, CS_MODE_64).disasm(pe.get_data(VALIDATION_RVA, 0x2a2), VALIDATION_RVA))
    for target in (PERMISSION_RVA, FILTER_RVA):
        assert any(i.mnemonic == 'call' and i.op_str == hex(target) for i in validation)
    assert any(i.mnemonic == 'lea' and i.op_str == 'rdx, [rsi + 0x80]' for i in validation)
    assert any(i.mnemonic == 'lea' and i.op_str == 'r8, [rsi + 0xc8]' for i in validation)
    stack_lookup = pe.get_data(STACK_LOOKUP_RVA, STACK_LOOKUP_END - STACK_LOOKUP_RVA)
    entry = list(decoder.disasm(stack_lookup[:14], STACK_LOOKUP_RVA))
    assert sum(i.size for i in entry) == 14
    assert all(i.mnemonic not in ('call', 'jmp') and 'rip' not in i.op_str for i in entry)
    # Both slot capacity and mining/logging's full-container test resolve the
    # same static row before reading MaxStackCount. No separate capacity bypass.
    for start, size in [(MAXIMUM_RVA, 0x40), (FULL_TEST_RVA, 0xa2), (FULL_TEST2_RVA, 0xf3)]:
        callers = list(decoder.disasm(pe.get_data(start, size), start))
        assert any(i.mnemonic == 'call' and i.op_str == hex(STACK_LOOKUP_RVA) for i in callers)
        assert any('0x78]' in i.op_str for i in callers)
    production = list(decoder.disasm(pe.get_data(PRODUCTION_RVA, 0x390), PRODUCTION_RVA))
    assert any(i.mnemonic == 'call' and i.op_str == hex(FULL_TEST_RVA) for i in production)
    if DEDICATED_SERVER:
        # Distinguish this getter from three identical-looking module getters.
        call = next(decoder.disasm(pe.get_data(MODULE_RVA + 9, 5), MODULE_RVA + 9))
        assert (call.mnemonic, call.op_str) == ('call', '0x2880d70')
        name = next(decoder.disasm(pe.get_data(0x2880db6, 7), 0x2880db6))
        name_rva = name.address + name.size + name.operands[1].mem.disp
        assert pe.get_data(name_rva, 80).decode('utf-16-le').split('\0')[0] == 'PalMapObjectItemContainerModule'
    def array(name, value):
        return f'inline constexpr std::array<std::uint8_t, {len(value)}> {name}{{' + ','.join(f'0x{x:02x}' for x in value) + '};\n'
    generated = BUILD / 'generated'
    generated.mkdir(parents=True, exist_ok=True)
    header = '#pragma once\n#include <array>\n#include <cstdint>\nnamespace guard {\n'
    header += f'inline constexpr bool dedicated_server = {str(DEDICATED_SERVER).lower()};\n'
    for name, value in [('timestamp', pe.FILE_HEADER.TimeDateStamp), ('image_size', pe.OPTIONAL_HEADER.SizeOfImage),
                        ('permission_rva', PERMISSION_RVA), ('filter_rva', FILTER_RVA),
                        ('maximum_rva', MAXIMUM_RVA), ('none_rva', none_rva),
                        ('transport_rva', TRANSPORT_RVA), ('transport_patch_rva', TRANSPORT_PATCH_RVA),
                        ('module_rva', MODULE_RVA), ('container_rva', CONTAINER_RVA),
                        ('static_data_rva', STATIC_DATA_RVA), ('stack_lookup_rva', STACK_LOOKUP_RVA)]:
        header += f'inline constexpr std::uint32_t {name} = 0x{value:x};\n'
    header += array('permission', pe.get_data(PERMISSION_RVA, PERMISSION_END - PERMISSION_RVA))
    header += array('filter', pe.get_data(FILTER_RVA, FILTER_END - FILTER_RVA))
    header += array('maximum', pe.get_data(MAXIMUM_RVA, 0x40))
    header += array('stack_lookup', stack_lookup)
    header += array('transport', transport)
    header += array('module', pe.get_data(MODULE_RVA, MODULE_END - MODULE_RVA))
    header += array('container', pe.get_data(CONTAINER_RVA, CONTAINER_END - CONTAINER_RVA))
    header += array('static_data', pe.get_data(STATIC_DATA_RVA, 0x80))
    header += '}\n'
    (generated / 'binary_guard.hpp').write_text(header, encoding='utf-8')
    (BUILD / 'analysis.json').write_text(json.dumps({'game_sha256': digest, 'target': 'server' if DEDICATED_SERVER else 'client',
        'permission_rva': hex(PERMISSION_RVA), 'filter_rva': hex(FILTER_RVA),
        'maximum_rva': hex(MAXIMUM_RVA), 'none_rva': hex(none_rva),
        'transport_rva': hex(TRANSPORT_RVA), 'transport_patch_rva': hex(TRANSPORT_PATCH_RVA),
        'transport_original': pe.get_data(TRANSPORT_PATCH_RVA, 14).hex(),
        'stack_lookup_rva': hex(STACK_LOOKUP_RVA), 'stack_limit': 99999,
        'production_full_test_rva': hex(FULL_TEST_RVA)}, indent=2))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--toolset', default='version=14.44.35207')
    parser.add_argument('--parallel', type=int, default=4)
    parser.add_argument('--server', action='store_true')
    args = parser.parse_args()
    if args.server: configure_server()
    generate_guard()
    lua = load_lua_runtime()()
    for script in (MOD / 'mod/Scripts').rglob('*.lua'):
        lua.execute('assert(load(...))', script.read_text(encoding='utf-8'))
    env = toolset_environment(args.toolset)
    subprocess.run(['cmake', '-S', str(MOD / 'native'), '-B', str(BUILD), '-G', 'Visual Studio 17 2022', '-A', 'x64', '-T', args.toolset], env=env, check=True)
    command = ['cmake', '--build', str(BUILD), '--config', 'Game__Shipping__Win64', '--parallel', str(args.parallel)]
    if args.toolset.startswith('version='):
        command += ['--', '/p:VCToolsVersion=' + args.toolset.split('=', 1)[1]]
    subprocess.run(command, env=env, check=True)
    output = ROOT / 'dist/BetterStorage'
    if args.server: output /= 'server'
    stage = output / 'BetterStorage'
    # Remove obsolete capacity scripts from a previous staging run.
    for name in ('BlueprintStorage.lua', 'StorageWatch.lua', 'config.lua', 'GuildStorage.lua'):
        (stage / 'Scripts' / name).unlink(missing_ok=True)
    if args.server:
        stage.mkdir(parents=True, exist_ok=True)
        shutil.copy2(MOD / 'mod/enabled.txt', stage / 'enabled.txt')
    else:
        shutil.copytree(MOD / 'mod', stage, dirs_exist_ok=True)
    schema_stage = output / 'PalSchema/mods/BetterStorage'
    shutil.copytree(MOD / 'schema', schema_stage, dirs_exist_ok=True)
    data = json.loads((schema_stage / 'blueprints/storage.json').read_text(encoding='utf-8'))
    assert data['BP_PalGameSetting_C']['GuildChestSlotNum'] >= 54
    (stage / 'dlls').mkdir(exist_ok=True)
    shutil.copy2(BUILD / 'Game__Shipping__Win64/bin/BetterStorageNative.dll', stage / 'dlls/main.dll')
    dll = pefile.PE(str(stage / 'dlls/main.dll'))
    exports = {entry.name for entry in dll.DIRECTORY_ENTRY_EXPORT.symbols}
    assert {b'start_mod', b'uninstall_mod', b'luaopen_BetterStorage'} <= exports
    runtime_root = GAME_EXE.parents[3] / 'Mods/NativeMods/UE4SS'
    runtime = pefile.PE(str(runtime_root / 'UE4SS.dll'))
    runtime_exports = {entry.name for entry in runtime.DIRECTORY_ENTRY_EXPORT.symbols if entry.name}
    imports = {item.name for module in dll.DIRECTORY_ENTRY_IMPORT if module.dll.lower() == b'ue4ss.dll' for item in module.imports}
    assert imports and not (imports - runtime_exports), 'Missing UE4SS imports'
    (BUILD / 'import-audit.json').write_text(json.dumps({
        'target': 'server' if args.server else 'client', 'imports_verified': len(imports),
        'dll_sha256': hashlib.sha256((stage / 'dlls/main.dll').read_bytes()).hexdigest()}, indent=2))
    shutil.copy2(MOD / 'README.md', stage / 'README.md')
    archive_name = 'BetterStorage-0.1.0.zip'
    with zipfile.ZipFile(output / archive_name, 'w', zipfile.ZIP_DEFLATED) as archive:
        for root in (stage, schema_stage):
            for path in sorted(root.rglob('*')):
                if path.is_file(): archive.write(path, path.relative_to(output))
    print(output / archive_name)

if __name__ == '__main__': main()
