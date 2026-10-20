"""Offline UI lifecycle regression; does not start or install the game."""
from pathlib import Path
import sys
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / 'tools'))
from palmods import load_lua_runtime
lua = load_lua_runtime()()
lua.globals().MAIN = str(ROOT / 'mods/BetterExpedition/mod/Scripts/main.lua')
lua.execute((Path(__file__).parent / 'ui.lua').read_text(encoding='utf-8'))
