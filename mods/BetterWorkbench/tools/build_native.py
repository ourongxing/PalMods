"""Build and test the native bridge without writing to the game or sibling SDK.

--enable-readonly audits the pinned UE4SS 2281fa31 headers. Runtime imports are
audited separately; reflection and binary guards still run inside Palworld.
"""
from pathlib import Path
import hashlib
import re
import struct
import subprocess
import xml.etree.ElementTree as ET
import argparse
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[3] / 'tools'))
from palmods import GAME_EXE, PALCOMBO_BUILD, UE4SS_SOURCE, build_directory, ROOT as REPOSITORY_ROOT

ROOT = Path(__file__).resolve().parents[1]
CACHE = PALCOMBO_BUILD
if not (CACHE / 'Game__Shipping__Win64/lib/UE4SS.lib').is_file():
    legacy_cache = REPOSITORY_ROOT / '.tools/ue4ss-sdk-cache'
    if legacy_cache.is_dir():
        CACHE = legacy_cache
PROJECT = CACHE / 'PalComboFillerNative.vcxproj'
if not PROJECT.is_file():
    PROJECT = CACHE / 'MyCPPMods/PalComboFillerNative/PalComboFillerNative.vcxproj'
EXE = GAME_EXE
BUILD = build_directory('BetterWorkbench')
BUILD.mkdir(parents=True, exist_ok=True)
parser = argparse.ArgumentParser()
parser.add_argument('--enable-readonly', action='store_true')
parser.add_argument('--build-dir', type=Path, default=BUILD / 'native',
                    help='CMake output directory; use a fresh directory after moving the project')
parser.add_argument('--toolset', help='CMake MSVC toolset, e.g. version=14.44.35207; must match cached SDK libraries')
args = parser.parse_args()
if args.enable_readonly:
    pinned = REPOSITORY_ROOT / '.tools/sdk-2281fa31/source/RE-UE4SS-2281fa311e417b1dfddedbcd49972d764fddb244'
    cached = UE4SS_SOURCE
    matched = 0
    for prefix in ('UE4SS/include', 'deps/first'):
        for original in (pinned / prefix).rglob('*.hpp'):
            relative = original.relative_to(pinned)
            candidate = cached / relative
            if not candidate.exists() or candidate.read_bytes().replace(b'\r\n', b'\n') != original.read_bytes().replace(b'\r\n', b'\n'):
                raise SystemExit(f'Pinned header mismatch: {relative}')
            matched += 1
    if matched < 177:
        raise SystemExit('Pinned header audit incomplete')
    print(f'Pinned UE4SS 2281fa31 header audit: {matched} matches. Runtime struct validation still required.')
data = EXE.read_bytes()
game_hash = hashlib.sha256(data).hexdigest()
pe = struct.unpack_from("<I", data, 0x3c)[0]
sections = struct.unpack_from("<H", data, pe + 6)[0]
optional_size = struct.unpack_from("<H", data, pe + 20)[0]
def read_rva(rva, size):
    for index in range(sections):
        header = pe + 24 + optional_size + index * 40
        virtual, offset, raw_size, raw_offset = struct.unpack_from("<IIII", data, header + 8)
        if offset <= rva and rva + size <= offset + raw_size:
            return data[raw_offset + rva - offset:raw_offset + rva - offset + size]
    raise ValueError("RVA outside raw section")
prefix = read_rva(0x2fadaa0, 24)
counts_prefix = read_rva(0x2fa0020, 24)
batch_window = read_rva(0x30060ff, 0x3006155 - 0x30060ff)
counts_call_window = read_rva(0x30061db, 0x30061f1 - 0x30061db)
counts_call = read_rva(0x30061ec, 5)
assert counts_call[0] == 0xe8 and 0x30061ec + 5 + struct.unpack_from('<i', counts_call, 1)[0] == 0x2fa0020
call = read_rva(0x300611e, 5)
assert call[0] == 0xe8 and 0x300611e + 5 + struct.unpack_from("<i", call, 1)[0] == 0x2fadaa0
timestamp = struct.unpack_from("<I", data, pe + 8)[0]
image_size = struct.unpack_from("<I", data, pe + 24 + 56)[0]
(BUILD / "binary_guard.hpp").write_text(
    f"constexpr uint32_t expected_timestamp = 0x{timestamp:x};\n"
    f"constexpr uint32_t expected_image_size = 0x{image_size:x};\n"
    + 'constexpr char expected_game_hash[] = "' + game_hash + '";\n'
    + 'struct ActiveGuard { uintptr_t rva; std::array<uint8_t,24> bytes; };\n'
    + 'constexpr std::array active_guards{\n'
    + ',\n'.join('ActiveGuard{'+hex(rva)+', {'+','.join(hex(b) for b in read_rva(rva,24))+'}}'
        for rva in (0x2fad860,0x3012d70,0x300df10,0x32c6e10,0x32f4600,0x36971b0,0x36954b0,
                    0x32f34f0,0x2fa0d00,0x32f7e50,0x31cc070,0x326aa30,0x3306f40,0x34ee990,0x2d67dc0,0x300d010,0x528e0b0,0x32f5ee0,
                    0x2fff160,0x3083060,0x300e280,0x2e8d210,0x300ced0,0x2fa6c00,0xdbe790,0x2fa9650,
                    0x3008fae,0x300e344,0x300d02d,0x300e298,0x2fbc2f0,0x30135c5,0x3012f95))
    + '\n};\n'
    +
    "constexpr std::array<uint8_t, 24> expected_prefix{" + ",".join(hex(b) for b in prefix) + "};\n"
    "constexpr std::array<uint8_t, 24> expected_counts_prefix{" + ",".join(hex(b) for b in counts_prefix) + "};\n"
    + ''.join("constexpr std::array<uint8_t, 24> expected_" + name + "_prefix{" + ','.join(hex(b) for b in read_rva(rva, 24)) + "};\n"
              for name, rva in [('worker', 0x3005d80), ('data', 0x30f0fb0), ('row', 0x30ec350)])
    +
    f"constexpr std::array<uint8_t, {len(batch_window)}> expected_batch_window{{" + ",".join(hex(b) for b in batch_window) + "};\n"
    f"constexpr std::array<uint8_t, {len(counts_call_window)}> expected_counts_call_window{{" + ",".join(hex(b) for b in counts_call_window) + "};\n",
    encoding="utf-8")
ns = {"m": "http://schemas.microsoft.com/developer/msbuild/2003"}
xml = ET.parse(PROJECT)
groups = xml.findall("m:ItemDefinitionGroup", ns)
group = next(g for g in groups if "Game__Shipping__Win64|x64" in g.get("Condition", ""))
def values(field):
    return [value for value in group.find(field, ns).text.split(";") if value and not value.startswith("%(")]
includes = values("m:ClCompile/m:AdditionalIncludeDirectories")
options = group.find("m:ClCompile/m:AdditionalOptions", ns).text
includes.extend(re.findall(r'/external:I\s+"([^"]+)"', options))
# Projects copied from the former standalone checkout retain absolute SDK paths.
# Prefer freshly generated projects; this keeps the original local cache usable.
old_checkout = 'D:/Dev/PalCombo/NativeSrc'
new_checkout = ROOT.parent / 'PalCombo/native'
def relocate_cached_path(value):
    normalized = value.replace('\\', '/')
    if normalized.lower().startswith(old_checkout.lower() + '/'):
        suffix = normalized[len(old_checkout):].lstrip('/')
        if suffix.startswith('RE-UE4SS/'):
            normalized = UE4SS_SOURCE.as_posix() + '/' + suffix[len('RE-UE4SS/'):]
        elif suffix.startswith('build/'):
            normalized = CACHE.as_posix() + '/' + suffix[len('build/'):]
        else:
            normalized = new_checkout.as_posix() + '/' + suffix
    return normalized
includes = [relocate_cached_path(value) for value in includes]
definitions = values("m:ClCompile/m:PreprocessorDefinitions")
if args.enable_readonly:
    definitions.append('BETTERWORKBENCH_SDK_ABI_VERIFIED=1')
libraries = values("m:Link/m:AdditionalDependencies")
libraries = [(PROJECT.parent / relocate_cached_path(lib)).resolve().as_posix() if "\\" in lib or '/' in lib else lib for lib in libraries]
def quoted(value):
    return '[=[' + value.replace('\\', '/') + ']=]'
cmake = ["cmake_minimum_required(VERSION 3.22)", "project(BetterWorkbenchNativeCandidate LANGUAGES CXX)",
         "enable_testing()",
         "add_executable(BetterWorkbenchViewTests " + quoted((ROOT / 'tests/native/recipe_view_test.cpp').as_posix()) + ")",
         "target_compile_features(BetterWorkbenchViewTests PRIVATE cxx_std_20)",
         "add_test(NAME recipe_view_isolation COMMAND BetterWorkbenchViewTests)",
         "add_executable(BetterWorkbenchJobTests " + quoted((ROOT / 'tests/native/job_schedule_test.cpp').as_posix()) + ")",
         "target_compile_features(BetterWorkbenchJobTests PRIVATE cxx_std_20)",
         "target_compile_options(BetterWorkbenchJobTests PRIVATE /UNDEBUG)",
         "add_test(NAME native_job_schedule COMMAND BetterWorkbenchJobTests)",
         "add_library(BetterWorkbenchNative SHARED " + quoted((ROOT / "native/src/dllmain.cpp").as_posix()) + ")",
         "target_compile_features(BetterWorkbenchNative PRIVATE cxx_std_20)",
         "set_property(TARGET BetterWorkbenchNative PROPERTY MSVC_RUNTIME_LIBRARY MultiThreadedDLL)",
         "target_compile_options(BetterWorkbenchNative PRIVATE /EHsc /Zc:__cplusplus /utf-8)",
         "target_include_directories(BetterWorkbenchNative PRIVATE " + ' '.join(quoted(p) for p in [BUILD.as_posix(), *includes]) + ")",
         "target_compile_definitions(BetterWorkbenchNative PRIVATE " + ' '.join(quoted(d) for d in definitions) + ")",
         "target_link_libraries(BetterWorkbenchNative PRIVATE " + ' '.join(quoted(lib) for lib in libraries) + ")"]
(BUILD / "CMakeLists.txt").write_text('\n'.join(cmake), encoding="utf-8")
(BUILD / "game-sha256.txt").write_text(game_hash + '\n', encoding="ascii")
configure = ["cmake", "-S", str(BUILD), "-B", str(args.build_dir), "-G", "Visual Studio 17 2022", "-A", "x64"]
if args.toolset:
    configure.extend(['-T', args.toolset])
subprocess.run(configure, check=True)
build_command = ["cmake", "--build", str(args.build_dir), "--config", "Release", "--parallel", "4"]
version = re.search(r'(?:^|,)version=([^,]+)', args.toolset or '')
if version:
    # MSBuild's default toolset can override the version selected by CMake.
    build_command.extend(['--', '/p:VCToolsVersion=' + version.group(1)])
subprocess.run(build_command, check=True)
subprocess.run(["ctest", '--test-dir', str(args.build_dir), '-C', 'Release', '--output-on-failure'], check=True)
print('Current-workbench native crafting bridge compiled; not yet deployed.' if args.enable_readonly else
      'Disabled candidate compiled; not deployed.')
