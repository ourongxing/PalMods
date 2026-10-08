"""Run the actual Lua modules with Lua 5.4 via lupa; no engine required."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT.parents[1] / 'tools'))
from palmods import load_lua_runtime
LuaRuntime = load_lua_runtime()

lua = LuaRuntime(unpack_returned_tuples=True)
lua.globals().PROJECT_ROOT = ROOT.as_posix()
lua.execute((ROOT / "tests" / "run.lua").read_text(encoding="utf-8"))
