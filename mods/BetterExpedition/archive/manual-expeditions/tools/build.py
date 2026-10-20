"""Verify the supported native ABI, build and package; never install."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from palmods import GAME_EXE, UE4SS_ROOT, build_directory
from build_sdk import ensure_sdk, toolset_environment
import pefile

MOD = Path(__file__).resolve().parents[1]
BUILD = build_directory('BetterExpedition')
SUPPORTED_SHA256 = 'e590b5e7bfaa3fea40fab1a02cc72c8fc5fd6f8631ef2308e95ac56c25195837'


def generate_guard():
    with GAME_EXE.open('rb') as source:
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
    if digest != SUPPORTED_SHA256:
        raise SystemExit('Unsupported Palworld executable; re-analyze expedition code before building.')
    pe = pefile.PE(str(GAME_EXE), fast_load=True)
    # Include complete functions (including chained unwind fragments), exact
    # caller checks and the request-array ABI. Compare all before any hook.
    regions = [(0x3022c40, 0x350), (0x3009410, 0x259), (0x301cea0, 0x63),
               (0x32675c0, 0x7b), (0x3063eb0, 0x120), (0x30b9fe0, 0xa9), (0x32f34f0, 32),
               (0x2fff160, 32), (0x3019e10, 32)]
    header = '#pragma once\n#include <array>\n#include <cstdint>\n#include <cstddef>\nnamespace guard {\n'
    header += f'inline constexpr std::uint32_t timestamp=0x{pe.FILE_HEADER.TimeDateStamp:x};\n'
    header += f'inline constexpr std::uint32_t image_size=0x{pe.OPTIONAL_HEADER.SizeOfImage:x};\n'
    for i, (rva, size) in enumerate(regions):
        header += f'inline constexpr std::array<std::uint8_t,{size}> bytes{i}={{' + ','.join(map(str, pe.get_data(rva, size))) + '};\n'
    header += 'struct Region {std::uint32_t rva; const std::uint8_t* bytes; std::size_t size;};\n'
    header += f'inline constexpr std::array<Region,{len(regions)}> regions={{{{\n'
    header += ',\n'.join(f'{{0x{rva:x},bytes{i}.data(),bytes{i}.size()}}' for i, (rva, _) in enumerate(regions))
    header += '\n}};\n}\n'
    (BUILD / 'generated').mkdir(exist_ok=True)
    (BUILD / 'generated/binary_guard.hpp').write_text(header, encoding='utf-8')
    (BUILD / 'binary-analysis.json').write_text(json.dumps({'sha256': digest, 'regions': regions}, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--toolset', default='version=14.44.35207')
    parser.add_argument('--parallel', type=int, default=4)
    args = parser.parse_args()
    args.toolset = ensure_sdk(args.parallel, args.toolset)
    generate_guard()
    env = toolset_environment(args.toolset)
    subprocess.run(['cmake', '-S', str(MOD / 'native'), '-B', str(BUILD / 'native'),
                    '-G', 'Visual Studio 17 2022', '-A', 'x64', '-T', args.toolset,
                    '-DCMAKE_PROJECT_INCLUDE='], env=env, check=True)
    subprocess.run(['cmake', '--build', str(BUILD / 'native'), '--config', 'Game__Shipping__Win64',
                    '--parallel', str(args.parallel), '--', '/p:VCToolsVersion=' + args.toolset.split('=', 1)[1]], env=env, check=True)
    dll = BUILD / 'native/Game__Shipping__Win64/bin/BetterExpeditionNative.dll'
    runtime = pefile.PE(str(UE4SS_ROOT / 'UE4SS.dll'), fast_load=True)
    candidate = pefile.PE(str(dll), fast_load=True)
    runtime.parse_data_directories(directories=[0])
    candidate.parse_data_directories(directories=[0, 1])
    exports = {s.name for s in runtime.DIRECTORY_ENTRY_EXPORT.symbols if s.name}
    imports = {s.name for e in candidate.DIRECTORY_ENTRY_IMPORT if e.dll.lower() == b'ue4ss.dll' for s in e.imports}
    assert imports and not imports - exports, imports - exports
    assert {b'start_mod', b'uninstall_mod'} <= {s.name for s in candidate.DIRECTORY_ENTRY_EXPORT.symbols}
    output = ROOT / 'dist/BetterExpedition'
    stage = output / 'BetterExpedition'
    shutil.copytree(MOD / 'mod', stage, dirs_exist_ok=True)
    (stage / 'dlls').mkdir(exist_ok=True)
    shutil.copy2(dll, stage / 'dlls/main.dll')
    shutil.copy2(MOD / 'README.md', stage / 'README.md')
    archive = output / 'BetterExpedition-0.1.0.zip'
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
        for path in sorted(stage.rglob('*')):
            if path.is_file():
                z.write(path, path.relative_to(output))
    print(f'PASS: supported binary, native build, {len(imports)} runtime imports; {archive}')


if __name__ == '__main__':
    main()
