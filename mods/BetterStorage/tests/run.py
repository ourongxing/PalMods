"""Verify scoped base selection and a bootstrap without preview hooks."""
from pathlib import Path
import sys
import json

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from palmods import load_lua_runtime, UE4SS_ROOT, GAME_EXE
sys.path.insert(0, str(ROOT / 'mods/BetterBulkStorage/tests'))
from audit_interfaces import audit, INTERFACES
INTERFACES['CollectQuickStackTargetItemInfos'] = ('Pal.PalBaseCampUtility', ['WorldContextObject', 'TargetBaseCampID', 'TargetPlayerUId', 'StaticItemIds', 'OutItemInfos'])
INTERFACES['IsServer'] = ('Pal.PalUtility', ['WorldContextObject'])
INTERFACES['GetGameSetting'] = ('Pal.PalUtility', ['WorldContextObject'])

mod = ROOT / 'mods/BetterStorage'
source = (mod / 'mod/Scripts/main.lua').read_text(encoding='utf-8')
guild_source = (mod / 'mod/Scripts/GuildStorage.lua').read_text(encoding='utf-8')
audit(source + '\n' + guild_source, UE4SS_ROOT / 'UE4SS_ObjectDump.txt')
lua = load_lua_runtime()(unpack_returned_tuples=True)
lua.globals().SCRIPTS = str(mod / 'mod/Scripts').replace('\\', '/')
lua.execute((mod / 'tests/runtime.lua').read_text(encoding='utf-8'))
lua.execute((mod / 'tests/guild_storage.lua').read_text(encoding='utf-8'))
storage = json.loads((mod / 'schema/blueprints/storage.json').read_text(encoding='utf-8'))
assert set(storage) == {'BP_BuildObject_Shelf01_Stone_C', 'BP_BuildObject_Shelf07_Stone_C', 'BP_PalGameSetting_C'}
for name in ('BP_BuildObject_Shelf01_Stone_C', 'BP_BuildObject_Shelf07_Stone_C'):
    parameter = storage[name]['PalMapObjectItemChestParameter']
    assert parameter['SlotNum'] == 360
    assert parameter['TargetTypesA'] == ['Blueprint'] and parameter['TargetTypesB'] == []
assert storage['BP_PalGameSetting_C']['GuildChestSlotNum'] == 360
assert set(p.name for p in (mod / 'mod/Scripts').glob('*.lua')) == {'main.lua', 'GuildStorage.lua'}
assert all(word not in source + guild_source for word in ('LoopAsync', 'NotifyOnNewObject', 'growBlueprintStorage'))
print('PASS: data capacity/filter patches with event-triggered guild migration, no periodic discovery')
native = (mod / 'native/src/main.cpp').read_text(encoding='utf-8')
assert 'ordered_transfer' not in native
assert 'PreventOriginalFunctionCall' not in native
assert 'preview_state' not in native
assert not (mod / 'mod/Scripts/Preview.lua').exists()
# The real vanilla helper sets its per-chest same-type flag before attempting
# a merge, and skips empty slots when that flag is false. Remote candidates
# therefore cannot introduce a new item type into an empty/different chest.
import pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_64
pe = pefile.PE(str(GAME_EXE), fast_load=True)
dump = (UE4SS_ROOT / 'UE4SS_ObjectDump.txt').read_text(encoding='utf-8')
assert 'PalGameSetting:GuildChestSlotNum [o: 1E60]' in dump
assert 'grow_blueprint_storage' not in native
assert 'PalBaseCampManager:OnCreateMapObjectModelInServer:CreatedModel [o: 0]' in dump
# Native growth reads the existing count, subtracts it from the requested final
# count, appends real slots, preserves their container IDs and broadcasts updates.
growth = {i.address: (i.mnemonic, i.op_str) for i in
          Cs(CS_ARCH_X86, CS_MODE_64).disasm(pe.get_data(0x2fa6c00, 0x149), 0x2fa6c00)}
for address, expected in {
    0x2fa6c19: ('call', 'qword ptr [rax + 0x2b0]'),
    0x2fa6c28: ('sub', 'r8d, edi'),
    0x2fa6c63: ('call', '0x2f98910'),
    0x2fa6c6e: ('mov', 'dword ptr [rax + 0x118], edi'),
    0x2fa6c74: ('movups', 'xmm0, xmmword ptr [rbx + 0x38]'),
    0x2fa6c88: ('mov', 'qword ptr [r14 + rcx], rsi'),
    0x2fa6d38: ('call', '0xba5e80'),
}.items():
    assert growth[address] == expected
instructions = {i.address: (i.mnemonic, i.op_str) for i in
                Cs(CS_ARCH_X86, CS_MODE_64).disasm(pe.get_data(0x2da9a60, 0x259), 0x2da9a60)}
for address, expected in {
    0x2da9ac3: ('xor', 'r13b, r13b'),
    0x2da9b1e: ('cmp', 'rax, qword ptr [r14]'),
    0x2da9b21: ('jne', '0x2da9bbd'),
    0x2da9b2d: ('mov', 'r13b, 1'),
    0x2da9bca: ('test', 'r13b, r13b'),
    0x2da9bcd: ('je', '0x2da9c78'),
}.items():
    assert instructions[address] == expected
# The original local-player entry delegates to this same explicit-base collector.
call = next(Cs(CS_ARCH_X86, CS_MODE_64).disasm(pe.get_data(0x2fa0cbc, 5), 0x2fa0cbc))
assert (call.mnemonic, call.op_str) == ('call', '0x2db0a90')
print('PASS: scoped base selection, exact vanilla collector with selected remote base, physical-base preservation, no preview/transfer override')
