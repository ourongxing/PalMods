"""Compile the UE 5.1.1 editor project using Unreal's bundled .NET runtime."""
from pathlib import Path
import os
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from palmods import UNREAL_ROOT

project = Path(__file__).resolve().parents[1] / 'native/Pal.uproject'
engine = UNREAL_ROOT / 'Engine'
dotnet = engine / 'Binaries/ThirdParty/DotNet/6.0.302/windows/dotnet.exe'
env = os.environ.copy()
env.update(DOTNET_ROOT=str(dotnet.parent), DOTNET_MULTILEVEL_LOOKUP='0')
subprocess.run([
    str(dotnet), str(engine / 'Binaries/DotNET/UnrealBuildTool/UnrealBuildTool.dll'),
    'PalEditor', 'Win64', 'Development', str(project), '-WaitMutex',
], cwd=engine / 'Source', env=env, check=True)
