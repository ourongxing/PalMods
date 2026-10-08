# PalMods

Palworld mod 源码仓库。

| Mod | 功能 |
| --- | --- |
| [BetterWorkbench](mods/BetterWorkbench/README.md) | 同工作台配方穿透、材料滚动、即时分解 |
| [PalCombo](mods/PalCombo/README.md) | 技能槽 1 → 2 连招，槽 3 填空 |
| [UpdraftElevator](mods/UpdraftElevator/README.md) | 三种尺寸的起跳升空气流建筑 |
| [PointBlankBurstSkills](mods/PointBlankBurstSkills/README.md) | 让熔岩爆发、岩爆和毒雨改为贴脸释放 |

## 构建与测试

在仓库根目录的 PowerShell 执行：

```powershell
python tools/build.py all --toolset version=14.44.35207 --parallel 4
python tools/build.py BetterWorkbench
python tools/build.py PalCombo UpdraftElevator
python tools/build.py sdk --rebuild-sdk --toolset version=14.44.35207
python tools/build.py --dry-run

python tools/test.py
python -m unittest discover -s tools/tests
```

不指定名称时构建全部 mod。原生 mod 构建前准备共享 UE4SS SDK，任一步失败即停止。
构建产物保存在 `.build/` 和 `dist/`；安装命令见各 mod 文档。

| 参数 | 用途 |
| --- | --- |
| `--parallel N` | SDK 和 mod 的 CMake 并行数，默认 4；UE 由 UnrealBuildTool 管理 |
| `--toolset version=…` | SDK、CMake 和 MSBuild 工具集；默认依次使用 `VCToolsVersion`、已有 SDK 工具集、CMake 默认值 |
| `--rebuild-sdk` | 重新配置、编译和导出 SDK；默认复用有效共享包 |
| `--dry-run` | 预览步骤和产物路径 |

`tools/test.py --skip-native` 运行 Lua／Schema 回归；完整测试另运行三个独立 C++ 测试。

| 目标 | 步骤 | 主要产物 |
| --- | --- | --- |
| sdk | 编译 UE4SS、导出 CMake 包 | `.build/UE4SS/PalModsSDKConfig.cmake`、`sdk.json` |
| PalCombo | 编译 DLL | `.build/PalCombo/Game__Shipping__Win64/bin/PalComboFillerNative.dll` |
| BetterWorkbench | 头文件审核、编译、C++ 测试、导入审核 | `.build/BetterWorkbench/native/Release/BetterWorkbenchNative.dll`、`import-audit.json` |
| UpdraftElevator | 编辑器构建、生成资源、Cook、打包 | `dist/UpdraftElevator/UpdraftElevator-v9.zip` |
| PointBlankBurstSkills | JSON 校验、暂存 | `.build/PointBlankBurstSkills/stage/Mods/PalSchema/mods/PointBlankBurstSkills/` |

2026-10-08：本机全部构建通过；共享 SDK 在新目录中从现有源码副本重建，并由两个原生 mod 链接通过。
新机器的依赖获取和游戏内验收需另行验证。

## 环境

| 依赖 | 版本／安装要求 | 用途 |
| --- | --- | --- |
| Windows x64、Git | Git 加入 PATH | 构建环境、源码与子模块 |
| Python | 3.12 x64、pip、venv | 脚本和 `requirements-dev.txt` |
| Visual Studio 2022／Build Tools | C++ 桌面开发、MSVC v143；UE4SS 要求 14.43+，本机使用 14.44.35207 | 原生编译 |
| Windows SDK | 本机使用 10.0.26100.0 | MSVC、UE |
| CMake／CTest | 3.22+，本机使用 4.4.3 | 原生构建与回归 |
| Rust／Cargo | MSVC 工具链；本机使用 1.98.1 | UE4SS 的 patternsleuth_bind |
| Unreal Engine | 5.1.1，含 Win64 编辑器和 Cook 工具 | 气流资源 |
| [repak](https://github.com/trumank/repak/releases) | 本机使用 0.2.3；支持 V11、Zlib，保存为 `tools/bin/repak.exe` | PAK 打包 |
| [RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) | 完整源码及子模块，目标提交 `2281fa311e417b1dfddedbcd49972d764fddb244` | 共享 SDK |
| UE4SS、PalSchema、Palworld | 匹配的游戏安装；本机 UE4SS 为 v3.0.1 Beta #0 / `2281fa31` | 运行 mod、二进制审核 |

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements-dev.txt
python -m pip check
```

无法激活时使用 `.venv/Scripts/python.exe`。也支持安装 Python 包到 `.tools/python/`。

### 路径

路径由 `tools/palmods.py` 和 `tools/paths.ps1` 管理，环境变量可覆盖默认值：

| 变量 | 默认路径 |
| --- | --- |
| `PALWORLD_ROOT` | `G:/SteamLibrary/steamapps/common/Palworld` |
| `UNREAL_ROOT` | `D:/Epic Games/UE_5.1` |
| `REPAK` | `tools/bin/repak.exe` |
| `UE4SS_SOURCE` | `.tools/RE-UE4SS` |
| `UE4SS_BUILD` | `.build/UE4SS` |
| `PALCOMBO_BUILD` | `.build/PalCombo` |

游戏布局：

```text
<PALWORLD_ROOT>/
  Pal/Binaries/Win64/Palworld-Win64-Shipping.exe
  Mods/NativeMods/UE4SS/
    UE4SS.dll
    Mods/PalSchema/
```

### UE4SS 源码与 SDK

```powershell
.\tools/setup_ue4ss.ps1
```

脚本固定目标提交并初始化子模块。Unreal 和 patternsleuth 子模块使用 GitHub SSH，需具备认证及仓库访问权限。
`Permission denied (publickey)` 检查 SSH；`Repository not found` 检查地址及访问权。
首次 SDK 配置需要 GitHub 和 crates.io 网络。

本机 `.tools/RE-UE4SS` 为无 `.git` 的源码副本，须备份完整 Unreal 源码及生成头文件。
尝试重新获取时使用 `-DependencyDirectory .tools/RE-UE4SS-fresh`，再设置 `UE4SS_SOURCE`。
更换工具集时将 `UE4SS_BUILD` 指向新目录，避免 CMake 已固定的工具集冲突。

历史库包可显式导入：

```powershell
python tools/build_sdk.py --import-project .tools/ue4ss-sdk-cache/MyCPPMods/PalComboFillerNative/PalComboFillerNative.vcxproj --cache-root .tools/ue4ss-sdk-cache --old-root D:/Dev/PalCombo/NativeSrc --toolset version=14.44.35207
```

导入包的 `sdk.json` 标记为 `legacy-import`，链接库仍位于原缓存目录。

### BetterWorkbench 参考头文件

构建前建立固定 ABI 审核快照：

```powershell
$sdkRevision = '2281fa311e417b1dfddedbcd49972d764fddb244'
New-Item -ItemType Directory -Path .tools/sdk-2281fa31/source -Force | Out-Null
Invoke-WebRequest "https://github.com/UE4SS-RE/RE-UE4SS/archive/$sdkRevision.zip" -OutFile .tools/sdk-2281fa31/source.zip
Expand-Archive .tools/sdk-2281fa31/source.zip -DestinationPath .tools/sdk-2281fa31/source -Force
```

本机审核使用的 SHA-256：

| 文件 | SHA-256 |
| --- | --- |
| Palworld EXE | `e590b5e7bfaa3fea40fab1a02cc72c8fc5fd6f8631ef2308e95ac56c25195837` |
| UE4SS.dll | `21b691a69a20c0801f465369d4fcbca7d7444764022fac2a7e8edc7709ef92b8` |

游戏版本变化后，需重新分析调用位置和二进制保护。

## 新增原生 mod

共享 SDK 工程位于 `tools/sdk/`，构建与导出逻辑位于 `tools/build_sdk.py`。
`PalModsSDKProbe` 提供 Shipping 配置的头文件、宏与链接库，导出目标 `PalMods::UE4SS`。

在新 mod 的 CMake 工程中使用 `find_package(PalModsSDK CONFIG REQUIRED)`，链接 `PalMods::UE4SS`；
在 `tools/build.py` 注册构建命令、产物路径和 SDK 依赖。

## 目录与迁移

| 目录 | 内容 |
| --- | --- |
| `mods/<Mod>/mod/` | Lua、配置、安装说明；PalSchema 数据按各 mod 安装布局使用 |
| `native/`、`tests/`、`tools/`、`docs/`、`data/`、`assets/` | 原生源码、测试、脚本、文档、元数据、美术源文件 |
| `.tools/` | 本地 SDK、外部工具及 Python 包 |
| `.build/<目标>/` | 编译产物、日志、暂存、部署备份和验证记录 |
| `dist/<Mod>/` | 发布包 |

迁移时保留完整 SDK 源码、共享包引用的库、参考头文件、repak、游戏运行库、存档和 `BetterWorkbench/Jobs/`。
UE 缓存、生成的 `native/Content/`、Python 环境及发布包可重建。
归档 `.build/` 中的部署备份和验证记录，再清理编译缓存；跨电脑重新生成 CMake 工程。
