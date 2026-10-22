"""Build the guarded per-Pal awakening gate and package it; never deploy."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
from zipfile import ZipFile, ZIP_DEFLATED

MOD = Path(__file__).resolve().parents[1]
ROOT = MOD.parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from palmods import GAME_EXE, UE4SS_ROOT
from build_sdk import ensure_sdk, toolset_environment
import pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

BUILD = ROOT / '.build/AwakeningTrust/native'
EXPECTED = 'e590b5e7bfaa3fea40fab1a02cc72c8fc5fd6f8631ef2308e95ac56c25195837'
HOOKS = [0x2e79290,0x2e7c6c0,0x2e76eb0,0x2e79380,0x2e7c7b0,0x2e76fa0,0x2e721f0,0x2e794e0,0x2e7c8f0,0x2e770e0]
CALCULATORS = [0x2f16ea0,0x2f15260,0x2f166d0]
ROW_CALLS = [0x2e792b1,0x2e7c6e1,0x2e76ed1,0x2e793a7,0x2e7c7d7,0x2e76fc7]
DETAIL_ROW_CALLS = [0x2e79509,0x2e7c919,0x2e77109]
RANK_RVA = 0x2e78c00
DEDICATED_SERVER = False

def configure_server():
    globals().update({
        'DEDICATED_SERVER': True,
        'GAME_EXE': Path(r'G:/PalworldTestServer/Pal/Binaries/Win64/PalServer-Win64-Shipping-Cmd.exe'),
        'UE4SS_ROOT': Path(r'G:/PalworldTestServer/Mods/NativeMods/UE4SS'),
        'BUILD': ROOT / '.build/AwakeningTrust/server-native',
        'EXPECTED': '6f929673e7ac637d591d6f3454dbd396be7911093311cb8b24af3a152b217f49',
        'HOOKS': [0x2d23a70,0x2d26e70,0x2d21690,0x2d23b60,0x2d26f60,0x2d21780,0x2d1c9d0,0x2d23cc0,0x2d270a0,0x2d218c0],
        'CALCULATORS': [0x2dc1530,0x2dbf8f0,0x2dc0d60],
        'ROW_CALLS': [0x2d23a91,0x2d26e91,0x2d216b1,0x2d23b87,0x2d26f87,0x2d217a7],
        'DETAIL_ROW_CALLS': [0x2d23ce9,0x2d270c9,0x2d218e9],
        'RANK_RVA': 0x2d233e0,
    })


def generate_guard():
    digest = hashlib.file_digest(GAME_EXE.open('rb'), 'sha256').hexdigest()
    if digest != EXPECTED:
        raise SystemExit('Unsupported target binary; re-analyze before updating native guards')
    pe = pefile.PE(str(GAME_EXE), fast_load=True)
    decoder = Cs(CS_ARCH_X86, CS_MODE_64)
    for i, rva in enumerate(HOOKS[:6]):
        code = list(decoder.disasm(pe.get_data(rva, 0x180), rva))
        assert any(x.mnemonic == 'call' and x.op_str == hex(HOOKS[6]) for x in code)
        assert any(x.mnemonic == 'call' and x.op_str == hex(CALCULATORS[i%3]) for x in code)
        assert any(x.mnemonic=='call' and x.address+5==ROW_CALLS[i] and x.op_str==hex(HOOKS[6]) for x in code)
        assert any(x.mnemonic == 'mulss' and x.op_str.endswith(hex(0x70+4*(i%3)) + ']') for x in code)
        # HP reads friendship points directly; other getters may call the
        # individual's rank accessor instead of reading points themselves.
        if i % 3 == 0:
            awakening_offset = '0x421' if i < 3 else '0x51'
            assert any(x.mnemonic == 'cmp' and awakening_offset in x.op_str for x in code)
            friendship_offset = '0x6bc' if i < 3 else '0x2ec'
            assert any(friendship_offset in x.op_str for x in code)
    for rva in CALCULATORS:
        code = list(decoder.disasm(pe.get_data(rva, 0x80), rva))
        assert any(x.mnemonic == 'mulss' and 'xmm1' in x.op_str for x in code)
    for i,rva in enumerate(HOOKS[7:]):
        code=list(decoder.disasm(pe.get_data(rva,0x100),rva))
        assert any(x.mnemonic=='call' and x.address+5==DETAIL_ROW_CALLS[i] and x.op_str==hex(HOOKS[6]) for x in code)
        assert any(x.mnemonic=='mulss' and x.op_str.endswith(hex(0x70+4*i)+']') for x in code)
        assert any(x.mnemonic=='cmp' and '[rdi]' in x.op_str for x in code)
    generated = BUILD / 'generated'
    generated.mkdir(parents=True, exist_ok=True)
    header = '#pragma once\n#include <array>\n#include <cstdint>\nnamespace guard {\n'
    for key, value in [('timestamp', pe.FILE_HEADER.TimeDateStamp), ('image_size', pe.OPTIONAL_HEADER.SizeOfImage),
                       ('row_rva', HOOKS[6]), ('rank_rva', RANK_RVA)]:
        header += f'inline constexpr std::uint32_t {key}=0x{value:x};\n'
    header += f'inline constexpr bool dedicated_server={str(DEDICATED_SERVER).lower()};\n'
    header += 'inline constexpr std::array<std::uint32_t,10> hook_rvas={' + ','.join(hex(r) for r in HOOKS) + '};\n'
    header += 'inline constexpr std::array<std::uint32_t,3> detail_row_calls={' + ','.join(hex(r) for r in DETAIL_ROW_CALLS) + '};\n'
    header += 'inline constexpr std::array<std::uint32_t,6> row_calls={' + ','.join(hex(r) for r in ROW_CALLS) + '};\n'
    regions = [(r, 0x180 if i<6 else 0x100) for i,r in enumerate(HOOKS)] + [(r,0x100) for r in CALCULATORS]+[(RANK_RVA,0x100)]
    for i,(rva,length) in enumerate(regions):
        header += f'inline constexpr std::array<std::uint8_t,{length}> bytes{i}={{' + ','.join(str(b) for b in pe.get_data(rva,length)) + '};\n'
    header += 'struct Region {std::uint32_t rva;const std::uint8_t* bytes;std::size_t size;};\n'
    header += f'inline constexpr std::array<Region,{len(regions)}> regions={{{{\n'
    header += ''.join(f'{{{hex(rva)},bytes{i}.data(),bytes{i}.size()}},\n' for i,(rva,_) in enumerate(regions))
    header += '}};\n}\n'
    (generated/'binary_guard.hpp').write_text(header,encoding='utf-8')
    (BUILD/'analysis.json').write_text(json.dumps({'game_sha256':digest,'hooks':[hex(r) for r in HOOKS],
        'save_offset':0x3d0,'awakening_offset_in_save':0x51,'friendship_point_offset_in_save':0x2ec,
        'target':'server' if DEDICATED_SERVER else 'client',
        'scope':'individual and save-parameter stat getters; native coefficient calculators'},indent=2),encoding='utf-8')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--parallel',type=int,default=4)
    parser.add_argument('--toolset',default='version=14.44.35207')
    parser.add_argument('--validation',action='store_true',help='Temporary read-only native interface checks; not a release build')
    parser.add_argument('--server',action='store_true',help='Build for the verified Windows dedicated server')
    args=parser.parse_args()
    if args.server: configure_server()
    args.toolset=ensure_sdk(args.parallel,args.toolset)
    generate_guard()
    env=toolset_environment(args.toolset)
    subprocess.run(['cmake','-S',str(MOD/'native'),'-B',str(BUILD),'-G','Visual Studio 17 2022','-A','x64','-T',args.toolset,
                    '-DAWAKENINGTRUST_VALIDATION='+('ON' if args.validation else 'OFF')],env=env,check=True)
    subprocess.run(['cmake','--build',str(BUILD),'--config','Game__Shipping__Win64','--parallel',str(args.parallel),
                    '--','/p:VCToolsVersion='+args.toolset.split('=',1)[1]],env=env,check=True)
    subprocess.run([str(BUILD/'Game__Shipping__Win64/bin/AwakeningTrustRulesTest.exe')],check=True)
    dll=BUILD/'Game__Shipping__Win64/bin/AwakeningTrustNative.dll'
    candidate=pefile.PE(str(dll)); runtime=pefile.PE(str(UE4SS_ROOT/'UE4SS.dll'))
    exports={s.name for s in runtime.DIRECTORY_ENTRY_EXPORT.symbols if s.name}
    imports={s.name for e in candidate.DIRECTORY_ENTRY_IMPORT if e.dll.lower()==b'ue4ss.dll' for s in e.imports}
    assert imports and not imports-exports
    assert {b'start_mod',b'uninstall_mod'} <= {s.name for s in candidate.DIRECTORY_ENTRY_EXPORT.symbols}
    (BUILD/'import-audit.json').write_text(json.dumps({'dll_sha256':hashlib.sha256(dll.read_bytes()).hexdigest(),
        'verified_imports':len(imports)},indent=2),encoding='utf-8')
    output=ROOT/'dist/AwakeningTrust'
    if args.server: output/='server'
    stage=output/'AwakeningTrust-0.3.0'
    (stage/'dlls').mkdir(parents=True,exist_ok=True)
    shutil.copy2(dll,stage/'dlls/main.dll');shutil.copy2(MOD/'README.md',stage/'README.md')
    (stage/'enabled.txt').write_text('',encoding='utf-8')
    archive=output/('AwakeningTrust-0.3.0-server.zip' if args.server else 'AwakeningTrust-0.3.0.zip')
    with ZipFile(archive,'w',ZIP_DEFLATED) as package:
        for relative in ['dlls/main.dll','README.md','enabled.txt']:
            package.write(stage/relative,'Mods/NativeMods/UE4SS/Mods/AwakeningTrust/'+relative)
    print(f'Built {archive}; native rules and {len(imports)} runtime imports verified')


if __name__=='__main__':main()
