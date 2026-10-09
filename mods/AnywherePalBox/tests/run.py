"""Exercise the real entry point and audit calls against the installed reflection dump."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from palmods import load_lua_runtime, UE4SS_ROOT
INTERFACES = {
    'GetLocalPalPlayerController': ('Pal.PalUtility', ['WorldContextObject']),
    'GetPalmi': ('Pal.PalUtility', ['WorldContextObject']),
    'GetHUDService': ('Pal.PalUtility', ['WorldContextObject']),
    'GetBaseCampManager': ('Pal.PalUtility', ['WorldContextObject']),
    'GetLocalPlayerGuild': ('Pal.PalGroupUtility', ['WorldContextObject']),
    'GetId': ('Pal.PalBaseCampModel', []),
    'GetGroupIdBelongTo': ('Pal.PalBaseCampModel', []),
    'GetInsideBaseCampModel': ('Pal.PalInsideBaseCampCheckComponent', []),
    'K2_GetActorLocation': ('Engine.Actor', []),
    'TryGetModel': ('Pal.PalBaseCampManager', ['BaseCampId', 'OutModel']),
    'GetBuildingNum': ('Pal.PalBaseCampModel', []),
    'GetTransform': ('Pal.PalBaseCampModel', []),
    'IsAnyOverlayUIActive': ('Pal.PalHUDService', []),
    'IsAnyFadeWidgetActive': ('Pal.PalHUDService', []),
    'GetOwnerMapObjectInstanceId': ('Pal.PalBaseCampModel', []),
    'GetMapObjectManager': ('Pal.PalUtility', ['WorldContextObject']),
    'FindModel': ('Pal.PalMapObjectManager', ['InstanceId']),
    'GetConcreteModel': ('Pal.PalMapObjectModel', ['bIsForce']),
    'IsSameGuildInLocalPlayer': ('Pal.PalMapObjectBaseCampPoint', []),
    'OnTriggerInteract': ('Pal.PalMapObjectConcreteModelBase', ['Other', 'IndicatorType']),
}
MOD = ROOT / 'mods/AnywherePalBox'
source = (MOD / 'mod/Scripts/main.lua').read_text(encoding='utf-8')
for name, arguments in re.findall(r':(\w+)\(([^()]*)\)', source):
    if name in {'get', 'IsValid', 'ForEach', 'IsA', 'upper', 'match', 'GetAddress'}:
        continue
    assert name in INTERFACES, f'Unreviewed game call: {name}'
    count = len(arguments.split(',')) if arguments.strip() else 0
    assert count == len(INTERFACES[name][1]), f'Changed Lua argument count: {name}'
# TryGetModel includes a nested guid call and is checked explicitly.
assert 'manager:TryGetModel(guid(id), output)' in source
dump_path = UE4SS_ROOT / 'UE4SS_ObjectDump.txt'
if dump_path.exists():
    dump = dump_path.read_text(encoding='utf-8')
    functions = set(re.findall(r' Function /Script/(\w+\.\w+:\w+) ', dump))
    parameters = {}
    for key, name in re.findall(r'Property /Script/(\w+\.\w+:\w+):(\w+) ', dump):
        if name != 'ReturnValue':
            parameters.setdefault(key, []).append(name)
    for name, (owner, expected) in INTERFACES.items():
        key = f'{owner}:{name}'
        assert key in functions, f'Missing UFunction: {key}'
        assert parameters.get(key, []) == expected, f'Changed parameters: {key}'
    for member in ('PalMapObjectBaseCampPoint:BaseCampId',
                   'PalPlayerCharacter:InsideBaseCampCheckComponent'):
        assert '/Script/Pal.' + member + ' ' in dump, member
    print(f'PASS: {len(INTERFACES)} game interface signatures and terminal fields')
else:
    print('SKIP: game interface audit requires UE4SS_ObjectDump.txt')
for forbidden in ('RegisterHook(', 'StaticConstructObject(', 'LoadAsset(', 'PushContentToLayer', 'SetWorldLocation', 'LoopAsync(', 'LoopInGameThread', 'IsInputKeyDown'):
    assert forbidden not in source, f'Unexpected UI hook or actor mutation: {forbidden}'
if dump_path.exists():
    assert re.search(r'EPalInteractiveObjectIndicatorType::OpenPalBoxMenu .*\[v: 11\]', dump)
lua = load_lua_runtime()(unpack_returned_tuples=True)
lua.globals().PROJECT_ROOT = MOD.as_posix()
lua.execute((MOD / 'tests/run.lua').read_text(encoding='utf-8'))
print('AnywherePalBox runtime regressions passed')
