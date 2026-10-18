"""Exercise quota, durable claims, and failure/re-entry handling in Lua 5.4."""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parents[1] / 'tools'))
from palmods import load_lua_runtime
lua = load_lua_runtime()(unpack_returned_tuples=True)
lua.globals().PROJECT_ROOT = ROOT.as_posix()
lua.execute((ROOT / 'tests/run.lua').read_text(encoding='utf-8'))
ui = load_lua_runtime()(unpack_returned_tuples=True)
ui.globals().PROJECT_ROOT = ROOT.as_posix()
ui.execute((ROOT / 'tests/ui.lua').read_text(encoding='utf-8'))
feedback = load_lua_runtime()(unpack_returned_tuples=True)
feedback.globals().PROJECT_ROOT = ROOT.as_posix()
feedback.execute((ROOT / 'tests/feedback.lua').read_text(encoding='utf-8'))
for path in (ROOT / 'mod/Scripts').rglob('*.lua'):
    lua.execute('assert(load(...))', path.read_text(encoding='utf-8'))
print('BetterArena: Lua regression and syntax checks passed')
