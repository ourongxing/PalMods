"""Exercise the actual Lua planner, allocator, transaction and recipe adapter."""
from pathlib import Path
import sys

MOD = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(MOD.parents[1] / 'tools'))
from palmods import load_lua_runtime

lua = load_lua_runtime()(unpack_returned_tuples=True)
lua.globals().PROJECT_ROOT = MOD.as_posix()
lua.execute((MOD / 'tests/run.lua').read_text(encoding='utf-8'))
lua.execute((MOD / 'tests/runtime.lua').read_text(encoding='utf-8'))
lua.execute((MOD / 'tests/ui.lua').read_text(encoding='utf-8'))
# Parse every shipped script, including engine-only UI code.
for path in (MOD / 'mod/Scripts').rglob('*.lua'):
    lua.execute('assert(load(...))', path.read_text(encoding='utf-8'))
print('All BetterPalSouls offline checks passed (engine execution remains unverified).')
