"""Shared development paths and Lua 5.4 runtime for all PalMods tools."""
from pathlib import Path
import os
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.append(str(ROOT / '.tools/python'))


def configured_path(name, default):
    return Path(os.environ.get(name, str(default))).expanduser().resolve()


GAME_ROOT = configured_path('PALWORLD_ROOT', r'G:\SteamLibrary\steamapps\common\Palworld')
GAME_EXE = GAME_ROOT / 'Pal/Binaries/Win64/Palworld-Win64-Shipping.exe'
UE4SS_ROOT = GAME_ROOT / 'Mods/NativeMods/UE4SS'
UNREAL_ROOT = configured_path('UNREAL_ROOT', r'D:\Epic Games\UE_5.1')
UNREAL_EDITOR = UNREAL_ROOT / 'Engine/Binaries/Win64/UnrealEditor-Cmd.exe'
REPAK = configured_path('REPAK', ROOT / 'tools/bin/repak.exe')
PALCOMBO_BUILD = configured_path('PALCOMBO_BUILD', ROOT / 'PalCombo/NativeSrc/build')
UE4SS_SOURCE = ROOT / '.tools/RE-UE4SS'
if not UE4SS_SOURCE.is_dir():
    UE4SS_SOURCE = ROOT / 'PalCombo/NativeSrc/RE-UE4SS'


def load_lua_runtime():
    # A single repository environment is preferred; old local caches remain usable.
    for directory in (ROOT / '.tools/python', ROOT / 'BetterWorkbench/.tools/python',
                      ROOT / 'UpdraftElevator/work/lua-check'):
        if directory.is_dir():
            sys.path.append(str(directory))
    try:
        from lupa.lua54 import LuaRuntime
    except ImportError as error:
        raise SystemExit('Install dependencies: python -m pip install -r requirements-dev.txt') from error
    return LuaRuntime


def use_mod_directory(name):
    """Anchor legacy relative asset paths to the mod, independent of caller cwd."""
    directory = ROOT / name
    os.chdir(directory)
    return directory
