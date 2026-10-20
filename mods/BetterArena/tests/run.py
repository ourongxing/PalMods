"""Exercise quota, durable claims, and failure/re-entry handling in Lua 5.4."""
from pathlib import Path
import runpy
import sys
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parents[1] / 'tools'))
from palmods import load_lua_runtime
for name in ('run', 'ui', 'feedback', 'balance', 'reload', 'entry', 'remote', 'network', 'runtime'):
    lua = load_lua_runtime()(unpack_returned_tuples=True)
    lua.globals().PROJECT_ROOT = ROOT.as_posix()
    lua.execute((ROOT / f'tests/{name}.lua').read_text(encoding='utf-8'))
runpy.run_path(str(ROOT / 'tests/schema.py'))
for path in (ROOT / 'mod/Scripts').rglob('*.lua'):
    lua.execute('assert(load(...))', path.read_text(encoding='utf-8'))
print('BetterArena: Lua regression and syntax checks passed')
