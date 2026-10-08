"""Exercise the real Lua entry point with a simulated UE4SS lifecycle."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root.parents[1] / 'tools'))
from palmods import load_lua_runtime

for plain_list in (False, True):
    lua = load_lua_runtime()(unpack_returned_tuples=True)
    lua.globals().PROJECT_ROOT = root.as_posix()
    lua.globals().PLAIN_PASSIVE_LIST = plain_list
    lua.execute((root / 'tests/run.lua').read_text(encoding='utf-8'))
