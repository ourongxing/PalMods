"""Build, verify native ABI guards/imports, and package ExtraImplantDrops; no deployment."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from palmods import ROOT, GAME_EXE, UE4SS_ROOT, build_directory
from build_sdk import ensure_sdk, toolset_environment
import pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

MOD = Path(__file__).resolve().parents[1]
BUILD = build_directory('ExtraImplantDrops')
EXPECTED = 'e590b5e7bfaa3fea40fab1a02cc72c8fc5fd6f8631ef2308e95ac56c25195837'
BUILDER, KNIFE_CALL, GROW, PASSIVE = 0x2e7a830, 0x32fd561, 0xc00880, 0x2963430
PROCESSOR, PROCESSOR_CALL, CONSTRUCTOR = 0x2e77cc0, 0x2e7aa80, 0x2e6bf70
WORLD, PASSIVE_MANAGER, PASSIVE_RATE, COPY_NAMES, ITEM_BONUS = 0x32ec360, 0x32efa10, 0x3151080, 0xd37250, 0x2cab0b0


def generate_guard():
    digest = hashlib.file_digest(GAME_EXE.open('rb'), 'sha256').hexdigest()
    if digest != EXPECTED:
        raise SystemExit('Unsupported game binary; re-analyze the native death drop path first')
    pe = pefile.PE(str(GAME_EXE), fast_load=True)
    pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_EXCEPTION']])
    decoder = Cs(CS_ARCH_X86, CS_MODE_64)
    def instructions(rva, length):
        return {i.address: (i.mnemonic, i.op_str) for i in decoder.disasm(pe.get_data(rva, length), rva)}
    knife = instructions(0x32fd390, 0x249)
    assert knife[KNIFE_CALL] == ('call', hex(BUILDER))
    assert knife[0x32fd54c] == ('mov', 'qword ptr [rsp + 0x20], rbp')  # Trainer
    assert knife[0x32fd556] == ('mov', 'r8, rbx')  # Individual parameter
    assert knife[0x32fd559] == ('lea', 'rdx, [rsp + 0x30]')  # output TArray
    assert knife[0x32fd59d] == ('add', 'rbx, 0x28')
    assert knife[0x32fd598] == ('call', '0x317b260')  # game's inventory loop
    death = instructions(0x3006f20, 0x3b5)
    assert death[0x30071c3] == ('call', hex(BUILDER))
    assert death[0x300722f] == ('call', '0x2fa5ed0')  # original ground-drop loop
    builder = instructions(BUILDER, 0x430)
    assert builder[PROCESSOR_CALL] == ('call', hex(PROCESSOR))
    assert builder[0x2e7aa5b] == ('mov', 'byte ptr [rsp + 0x30], 0')
    passive = instructions(PASSIVE, 0x24)
    assert passive[0x2963445] == ('lea', 'rdx, [rcx + 0x460]')
    assert passive[0x296344f] == ('jmp', '0xd37250')  # TArray<FName> copy
    entries = instructions(0x2e77cc0, 0xd64)
    assert entries[0x2e7866c] == ('call', hex(GROW))
    assert entries[0x2e78678] == ('movups', 'xmm0, xmmword ptr [r12]')
    assert entries[0x2e7868c] == ('movsd', 'xmm0, qword ptr [r12 + 0x20]')
    assert entries[0x2e77ead] == ('call', hex(WORLD))
    assert entries[0x2e77eb2] == ('movss', 'xmm8, dword ptr [rax + 0x78]')
    assert entries[0x2e77ebb] == ('call', hex(PASSIVE_MANAGER))
    assert entries[0x2e77f65] == ('call', hex(PASSIVE_RATE))
    assert entries[0x2e77f6d] == ('addss', 'xmm6, dword ptr [rbp + 0x2d8]')
    assert entries[0x2e78623] == ('movss', 'dword ptr [rsp + 0x38], xmm8')
    rates = instructions(CONSTRUCTOR, 0x13f)
    assert rates[0x2e6c049] == ('movss', 'xmm2, dword ptr [rsp + 0x70]')
    assert rates[0x2e6c070] == ('movss', 'xmm1, dword ptr [rsp + 0x88]')
    assert rates[0x2e6c091] == ('mov', 'dword ptr [rsi + 8], eax')
    ctor = instructions(0x2e6bf70, 0x40)
    assert ctor[0x2e6bf92] == ('mov', 'qword ptr [rdx], r8')
    assert ctor[0x2e6bfa0] == ('movups', 'xmmword ptr [rdx + 0x10], xmm0')
    ends = {e.struct.BeginAddress: e.struct.EndAddress for e in pe.DIRECTORY_ENTRY_EXCEPTION}
    # This parameter getter is a leaf thunk and has no unwind directory entry.
    ends.setdefault(PASSIVE, PASSIVE + 0x24)
    regions = [(name, rva, ends[rva] - rva) for name, rva in [
        ('builder', BUILDER), ('knife', 0x32fd390), ('death', 0x3006f20),
        ('passives', PASSIVE), ('grow', GROW), ('processor', PROCESSOR),
        ('entry_constructor', CONSTRUCTOR), ('world_settings', WORLD),
        ('passive_manager', PASSIVE_MANAGER), ('passive_rate', PASSIVE_RATE),
        ('copy_names', COPY_NAMES), ('item_bonus', ITEM_BONUS)]]
    header = '#pragma once\n#include <array>\n#include <cstddef>\n#include <cstdint>\nnamespace guard {\n'
    for key, value in [('timestamp', pe.FILE_HEADER.TimeDateStamp), ('image_size', pe.OPTIONAL_HEADER.SizeOfImage),
                       ('builder_rva', BUILDER), ('knife_call_rva', KNIFE_CALL),
                       ('grow_rva', GROW), ('passive_offset', 0x460),
                       ('processor_rva', PROCESSOR), ('processor_call_rva', PROCESSOR_CALL),
                       ('world_settings_rva', WORLD), ('world_rate_offset', 0x78),
                       ('passive_manager_rva', PASSIVE_MANAGER), ('passive_rate_rva', PASSIVE_RATE),
                       ('copy_names_rva', COPY_NAMES), ('item_bonus_rva', ITEM_BONUS),
                       ('entry_constructor_rva', CONSTRUCTOR)]:
        header += f'inline constexpr std::uint32_t {key} = 0x{value:x};\n'
    for name, rva, length in regions:
        data = pe.get_data(rva, length)
        header += f'inline constexpr std::array<std::uint8_t, {length}> {name} = {{' + ','.join(f'0x{b:02x}' for b in data) + '};\n'
    header += 'struct Region { std::uint32_t rva; const std::uint8_t* bytes; std::size_t size; };\n'
    header += f'inline constexpr std::array<Region, {len(regions)}> regions = {{{{\n'
    for name, rva, _ in regions:
        header += f'{{0x{rva:x}, {name}.data(), {name}.size()}},\n'
    header += '}};\n}\n'
    (BUILD / 'generated').mkdir(exist_ok=True)
    (BUILD / 'generated/binary_guard.hpp').write_text(header, encoding='utf-8')
    (BUILD / 'analysis.json').write_text(json.dumps({'game_sha256': digest, 'scope': 'native Pal death drop builder',
        'regions': {name: {'rva': hex(rva), 'size': length} for name, rva, length in regions}}, indent=2), encoding='utf-8')
    print('PASS: native death/knife paths, game quantity modifiers and owning-array ABIs verified', flush=True)


def audit(dll):
    candidate = pefile.PE(str(dll))
    runtime = pefile.PE(str(UE4SS_ROOT / 'UE4SS.dll'))
    exports = {s.name for s in runtime.DIRECTORY_ENTRY_EXPORT.symbols if s.name}
    imported = {s.name for entry in candidate.DIRECTORY_ENTRY_IMPORT if entry.dll.lower() == b'ue4ss.dll'
                for s in entry.imports}
    if not imported or imported - exports:
        raise SystemExit(f'Missing UE4SS imports: {imported - exports}')
    assert {b'start_mod', b'uninstall_mod'} <= {s.name for s in candidate.DIRECTORY_ENTRY_EXPORT.symbols}
    report = {'dll_sha256': hashlib.sha256(dll.read_bytes()).hexdigest(), 'imports_verified': len(imported),
              'symbols': sorted(s.decode() for s in imported)}
    (BUILD / 'import-audit.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(f'PASS: all {len(imported)} UE4SS imports exported by installed runtime', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--toolset', default='version=14.44.35207')
    parser.add_argument('--parallel', type=int, default=4)
    args = parser.parse_args()
    args.toolset = ensure_sdk(args.parallel, args.toolset)
    generate_guard()
    env = toolset_environment(args.toolset)
    subprocess.run(['cmake', '-S', str(MOD / 'native'), '-B', str(BUILD), '-G', 'Visual Studio 17 2022',
                    '-A', 'x64', '-T', args.toolset], env=env, check=True)
    subprocess.run(['cmake', '--build', str(BUILD), '--config', 'Game__Shipping__Win64',
                    '--parallel', str(args.parallel), '--', '/p:VCToolsVersion=' + args.toolset.split('=', 1)[1]], env=env, check=True)
    dll = BUILD / 'Game__Shipping__Win64/bin/ExtraImplantDropsNative.dll'
    audit(dll)
    output = ROOT / 'dist/ExtraImplantDrops'
    stage = output / 'ExtraImplantDrops'
    shutil.copytree(MOD / 'mod', stage, dirs_exist_ok=True)
    (stage / 'dlls').mkdir(exist_ok=True)
    shutil.copy2(dll, stage / 'dlls/main.dll')
    shutil.copy2(MOD / 'README.md', stage / 'README.md')
    archive = output / 'ExtraImplantDrops-1.0.0.zip'
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
        for path in sorted(stage.rglob('*')):
            if path.is_file(): z.write(path, path.relative_to(output))
    print(archive)


if __name__ == '__main__': main()
