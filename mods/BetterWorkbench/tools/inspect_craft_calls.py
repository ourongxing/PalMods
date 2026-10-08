"""Locate direct call sites and unwind function boundaries in the local game PE.

Read-only analysis. Addresses are local-build evidence, never installed hooks.
"""
from pathlib import Path
from bisect import bisect_right
import json
import struct

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from palmods import GAME_EXE, build_directory
import pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

ROOT = Path(__file__).resolve().parents[1]
EXE = GAME_EXE
pe = pefile.PE(str(EXE), fast_load=True)
pe.parse_data_directories(directories=[pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_EXCEPTION']])
targets = {0x300a0c0: 'current_recipe', 0x300ced0: 'recipe_material_ids',
           0x2fadaa0: 'effective_demand', 0x300d010: 'input_slots',
           0x2fad860: 'effective_material_map', 0x2fbc2f0: 'native_item_transaction'}
ranges = sorted((entry.struct.BeginAddress, entry.struct.EndAddress)
                for entry in pe.DIRECTORY_ENTRY_EXCEPTION)
starts = [begin for begin, _ in ranges]
found = []
decoder = Cs(CS_ARCH_X86, CS_MODE_64)
decoded = {}
for section in pe.sections:
    if not section.Characteristics & 0x20000000:
        continue
    data = section.get_data()
    pos = 0
    while (pos := data.find(b'\xe8', pos)) >= 0:
        call = section.VirtualAddress + pos
        if pos + 5 <= len(data):
            target = call + 5 + struct.unpack_from('<i', data, pos + 1)[0]
            if target in targets:
                index = bisect_right(starts, call) - 1
                boundary = ranges[index] if index >= 0 and call < ranges[index][1] else None
                if not boundary:
                    pos += 1
                    continue
                if boundary not in decoded:
                    begin, end = boundary
                    code = pe.get_data(begin, end - begin)
                    decoded[boundary] = {instruction.address: instruction for instruction in
                                         decoder.disasm(code, begin)}
                instruction = decoded[boundary].get(call)
                if not instruction or instruction.mnemonic != 'call':
                    pos += 1
                    continue
                found.append({'target': targets[target], 'call_rva': hex(call),
                              'function_rva': hex(boundary[0]), 'instruction_verified': True})
        pos += 1
out = build_directory('BetterWorkbench') / 'craft-call-sites.json'
out.write_text(json.dumps(found, indent=2), encoding='utf-8')
for call in found:
    print(call['target'], call['call_rva'], 'function', call['function_rva'])
print('Instruction boundaries verified from PE unwind starts; signatures still require caller inspection.')
