"""Run real Lua persistence and editor flow against isolated fake widgets."""
from pathlib import Path
import base64
import json
import re
import struct
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from palmods import load_lua_runtime

lua = load_lua_runtime()(unpack_returned_tuples=True)
mod = ROOT / 'mods/CustomPresets'
scripts = mod / 'mod/Scripts'
lua.globals().SCRIPTS = scripts.as_posix()
with tempfile.TemporaryDirectory() as temporary:
    target = Path(temporary)
    (target / 'Scripts/CustomPresets').mkdir(parents=True)
    (target / 'presets/library').mkdir(parents=True)
    (target / 'Scripts/CustomPresets/UI.lua').write_bytes((scripts / 'CustomPresets/UI.lua').read_bytes())
    lua.globals().UI_PATH = (target / 'Scripts/CustomPresets/UI.lua').as_posix()
    lua.globals().PRESETS = (target / 'presets').as_posix()
    lua.execute((mod / 'tests/run.lua').read_text(encoding='utf-8'))
source = (scripts / 'CustomPresets/UI.lua').read_text(encoding='utf-8')
assert ':GetPadding(' not in source, 'WrapBoxSlot exposes Padding as a property, not a reflected getter'
assert 'original.Slot.Padding' in source
assert 'card.WidgetTree.RootWidget:AddChildToCanvas' not in source, 'Native card root must stay unchanged'
for forbidden in ('CreateDifficultySettingStrings', 'ConvertUIIndexToDifficulty',
                  'ConvertDifficultyToUIIndex', 'SetupSelections', 'output:set'):
    assert forbidden not in source, forbidden
assert ':ApplyWorldSettingToUI(' not in source, 'Oversized world settings cannot use Lua UFunction dispatch'
assert 'CustomPresetsNativeRefresh(s.Menu)' in source
assert 'CustomPresetsNativeCharacterRefresh(s.Menu)' in source
for unsafe in (':ApplyMakeInfo(', ':GetMakeData(', ':ConvertMakeInfo_HSVToRGB('):
    assert unsafe not in source, 'Character structs must use the sized native bridge'
assert 'lua.get_string(2)' not in (mod / 'native/src/main.cpp').read_text(encoding='utf-8'), 'Do not read slot 2 after userdata consumption'
native = (mod / 'native/src/main.cpp').read_text(encoding='utf-8') + (mod / 'native/src/PreviewImage.hpp').read_text(encoding='utf-8')
for guard in ('CustomPresetsNativeCharacterRefresh', 'ConvertMakeInfo_HSVToRGB', 'Character appearance types changed', 'ReadRenderTargetRaw', 'WICBitmapInterpolationModeFant', 'MOVEFILE_REPLACE_EXISTING', 'GetParmsSize()', 'field_size > size - offset', 'InitializeValue', 'CopyCompleteValue', 'DestroyValue'):
    assert guard in native, guard
export = ROOT / '.build/CustomPresets/world.json'
binding = ROOT / '.tools/RE-UE4SS/UE4SS/include/LuaType/LuaUFunction.hpp'
if export.exists() and binding.exists():
    document = json.loads(export.read_text(encoding='utf-8-sig'))
    function = next(e for e in document['Exports'] if e['ObjectName'] == 'ApplyWorldSettingToUI')
    raw = base64.b64decode(function['Data'])
    names = document['NameMap']
    assert names[struct.unpack_from('<I', raw, 18)[0]] == 'StructProperty'
    assert names[struct.unpack_from('<I', raw, 26)[0]] == 'WorldSetting'
    argument_bytes = struct.unpack_from('<I', raw, 42)[0]
    capacity = int(re.search(r'uint8_t data\[(0x[0-9a-fA-F]+)\]', binding.read_text()).group(1), 16)
    assert argument_bytes > capacity
    print(f'CONFIRMED: current game argument {argument_bytes} bytes exceeds legacy Lua call buffer {capacity} bytes')
print('PASS: world and character preset creation, selection, colors/voice, thumbnail lifecycle, rollback, isolation, original-preset protection, persistence and deferred actions')
