from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from palmods import load_lua_runtime, use_mod_directory
use_mod_directory('UpdraftElevator')
lua = load_lua_runtime()()
lua.execute('''
hooks = {}; insertions = 0; messages = {}
local entries = {
 {name='EPalBuildObjectTypeForUIDisplay::Other', value=48},
 {name='EPalBuildObjectTypeForUIDisplay::Ancient', value=49},
 {name='EPalBuildObjectTypeForUIDisplay::EPalBuildObjectTypeForUIDisplay_MAX', value=50},
}
categories = {IsValid=function() return true end}
function categories:ForEachName(callback)
 for _, entry in ipairs(entries) do callback(entry.name, entry.value) end
end
function categories:InsertIntoNames(name, value, index, shift)
 assert(index == 2 and shift == true)
 for _, entry in ipairs(entries) do
  if entry.value >= value then entry.value = entry.value + 1 end
 end
 table.insert(entries, index+1, {name=name, value=value})
 insertions = insertions + 1
end
function StaticFindObject(path)
 if path == '/Script/Pal.EPalBuildObjectTypeForUIDisplay' then return categories end
 if path == '/Script/Pal.Default__PalMasterDataTablesUtility' then
  return {GetLocalizedText=function(self, world, category, id)
   assert(world == 'world' and category == 18 and id == 'NAME_RECIPE_CodexWindTechnology')
   return translated
  end}
 end
 return {IsValid=function() return true end}
end
function RegisterHook(path, pre, post) hooks[path] = post or pre end
function print(message) table.insert(messages, message) end
function FName(value) return value end
''')
source = Path('mod/Scripts/main.lua').read_text(encoding='utf-8')
lua.execute(source)
lua.execute(source)  # Reload must reuse the category rather than shift vanilla values again.
lua.execute('''
assert(insertions == 1)
categories:ForEachName(function(name, value)
 if name:match('::Other$') then assert(value == 48) end
 if name:match('::Ancient$') then assert(value == 49) end
 if name:match('::CodexWindUpdraft$') then assert(value == 50) end
 if name:match('_MAX$') then assert(value == 51) end
end)
local hook = assert(hooks['/Script/Pal.PalUIUtility:GetBuildObjectUIDIsplayCategoryTextId'])
local output = {set=function(self, value) self.text = value end}
local wrap = function(value) return {get=function() return value end} end
for _, text in ipairs({'上升气流', '上升氣流', '上昇気流', 'Updraft Elevator'}) do
 translated = text
 hook(nil, wrap('world'), wrap(50), output)
 assert(output.text == text)
end
output.text = 'vanilla'
hook(nil, wrap('world'), wrap(48), output)
assert(output.text == 'vanilla')
for _, message in ipairs(messages) do assert(not message:find('Build category unavailable')) end
''')
sys.path.insert(0, str(Path('tools').resolve()))
from wind_data import build_rows
assert all(row['BuildingData']['TypeUIDisplay'] == 'CodexWindUpdraft'
           for row in build_rows().values() if 'BuildingData' in row)
print('PASS: dedicated updraft category, reload reuse, vanilla categories unchanged, four-language title')
