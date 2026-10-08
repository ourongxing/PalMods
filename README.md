# PalMods

四个 Palworld mod 的统一源码仓库。

| Mod | 功能 |
| --- | --- |
| [BetterWorkbench](mods/BetterWorkbench/README.md) | 同工作台配方穿透、材料滚动、即时分解 |
| [PalCombo](mods/PalCombo/README.md) | 技能槽 1 → 2 连招，槽 3 填空 |
| [UpdraftElevator](mods/UpdraftElevator/README.md) | 三种尺寸的起跳升空气流建筑 |
| [CloseRangeBurstSkills](mods/CloseRangeBurstSkills/README.md) | 缩短三种近身范围技能的 AI 最大施放距离 |

## 统一目录约定

```text
mods/
  BetterWorkbench/
  PalCombo/
  UpdraftElevator/
  CloseRangeBurstSkills/
tools/                 共享路径、依赖与测试入口
.tools/                本地 SDK、Python 依赖和外部工具（不提交）
.build/<Mod>/          编译、打包暂存、日志与部署备份（不提交）
dist/<Mod>/            发布包（不提交）
```

每个 mod 使用相同的目录职责；只创建实际需要的目录：

| 目录 | 内容 |
| --- | --- |
| `mod/` | 按游戏安装布局保存的 Lua、配置和使用说明；共同入口 `mod/Scripts/main.lua` |
| `native/` | C++ 原生源码；气流项目保留 UE 要求的 `Source/`、`Config/`、`.uproject` |
| `tests/` | Lua、Python 与 `tests/native/` C++ 回归，样例放 `tests/fixtures/` |
| `tools/` | 本 mod 的构建、校验、打包与部署脚本 |
| `docs/` | 接入、原生实现与开发文档 |
| `data/` | 构建所需的元数据、模板和 Schema |
| `assets/` | 美术源文件 |

源码目录与游戏安装目录分开：`mods/<名称>/mod/` 的内容安装到 UE4SS 的 `Mods/<名称>/`。
UpdraftElevator 的 PalSchema 配方和 PAK 由打包器另行生成到 `Mods/PalSchema/mods/UpdraftElevator/`。
CloseRangeBurstSkills 是纯 PalSchema 数据 mod，`mods/CloseRangeBurstSkills/mod/` 的内容安装到 `Mods/PalSchema/mods/CloseRangeBurstSkills/`。
Unreal 按引擎约定在 `native/` 下生成 `Binaries/`、`Intermediate/`、`Saved/` 等缓存，均忽略。

## 换电脑前先确认

**目前 Git 仓库不是完整、已验证的从零构建环境。** Lua／Schema 和独立 C++ 回归只需要公开工具；
气流资源可以用仓库源码和 UE 编辑器生成；PalCombo 和 BetterWorkbench 的完整原生构建还依赖
UE4SS 的 Unreal 子模块及 SDK 库。本机使用的依赖未提交，不能只复制 Git 仓库后就删除旧电脑的 `.tools/`。

| 流程 | Git clone 后还需要什么 | 当前验证范围 |
| --- | --- | --- |
| Lua／Schema 测试 | Python 和 Python 包 | 不需要游戏、UE 编辑器或 UE4SS SDK |
| 独立 C++ 测试 | CMake、MSVC、Windows SDK | 不链接 UE4SS；通过不代表 mod DLL 能构建 |
| PalCombo DLL | 完整 UE4SS 源码／子模块、Rust、CMake、MSVC、Windows SDK | 本机有历史 SDK 缓存；空机器重建尚未验收 |
| BetterWorkbench DLL | 上述 SDK 配置及库、固定头文件快照、匹配的游戏 EXE | 本机复用旧库；新路径下应优先重新生成 SDK 工程 |
| 气流 PAK／ZIP | UE 5.1.1、MSVC、Windows SDK、Python、repak | 本机完成过编辑器构建、生成和 Cook；新电脑尚未验收 |
| CloseRangeBurstSkills | 无编译步骤；运行时需要 PalSchema／UE4SS | 直接使用 `mod/` 内的 JSON |

下文命令都在仓库根目录的 PowerShell 执行。示例路径须换成新电脑的实际安装路径。

## 依赖清单与安装

| 依赖 | 版本／安装内容 | 用途和来源 |
| --- | --- | --- |
| Windows x64 | 本仓库完整原生流程按 Windows 编写 | BAT、MSVC、游戏 PE、Unreal 编辑器工具 |
| Git | Git for Windows，加入 PATH | 获取仓库、UE4SS、子模块和 CMake 下载的依赖；[官网](https://git-scm.com/downloads/win) |
| Python | 3.12 x64，包含 pip 和 venv | [官网](https://www.python.org/downloads/windows/)；建议新建 `.venv` |
| Python 包 | `requirements-dev.txt` | `lupa==2.8` 用于 Lua 5.4 测试；`jsonschema` 及其传递依赖 `referencing` 用于 Schema；`numpy`、`Pillow` 用于贴图生成；`pefile==2024.8.26` 用于导入审核；`capstone` 用于可选反汇编分析 |
| Visual Studio 2022／Build Tools 2022 | 安装“使用 C++ 的桌面开发”、MSVC v143 x64/x86 工具、Windows SDK | [官网](https://visualstudio.microsoft.com/downloads/)；UE 编辑器构建也需要 C++ 工具 |
| MSVC | UE4SS 检查要求 14.43+；本机使用安装目录版本 **14.44.35207** | SDK 库和 BetterWorkbench 使用相同工具集；只装 VS 而没装该组件不够 |
| Windows SDK | 本机成功气流构建使用 **10.0.26100.0** | VS Installer 的“单个组件”；其他版本尚未作为完整流程验收 |
| CMake | 3.22+；本机当前安装 4.4.3 | [官网](https://cmake.org/download/)；包含 CMake 和 CTest，并加入 PATH；最低要求不代表每个中间版本已验证 |
| Rust／Cargo | `x86_64-pc-windows-msvc`；SDK 最低检查 1.73，本机缓存记录 1.98.1 | [rustup](https://rustup.rs/)；UE4SS 的 `patternsleuth_bind` 经 Corrosion 编译 Rust，实际 crate 可能有更高要求 |
| Unreal Engine | **5.1.1**，含 Win64 编辑器、构建及 Cook 工具 | Epic Games Launcher 安装旧版本；不是任意 UE 5.x；构建脚本使用引擎自带 .NET 6.0.302，无须另外配置系统 .NET |
| repak CLI | 本机 `repak_cli 0.2.3` | [发布页](https://github.com/trumank/repak/releases)；下载 Windows 可执行文件并命名为 `repak.exe`，放到 `tools/bin/` 或配置 `REPAK`；EXE 被 Git 忽略 |
| RE-UE4SS SDK | 目标提交 `2281fa311e417b1dfddedbcd49972d764fddb244`，包含子模块 | [源码](https://github.com/UE4SS-RE/RE-UE4SS)；获取限制及本机副本见下一节 |
| UE4SS 运行库 | 当前实测日志为 v3.0.1 Beta #0、Git SHA `2281fa31` | 运行 mod 和 BetterWorkbench 导入审核需要游戏内实际 `UE4SS.dll`；源码 ZIP 不包含可用运行库 |
| PalSchema | 气流建筑和 CloseRangeBurstSkills 运行时依赖 | 不参与 C++ 编译；仓库只有 Schema 快照，没有打包 PalSchema 运行时；迁移时保留现有可用安装及版本记录 |
| Palworld | BetterWorkbench 需要对应游戏二进制 | 通过 Steam 安装／迁移；固定 RVA 和机器码审核不保证支持游戏更新，版本指纹见下文 |

安装后先检查工具，再创建虚拟环境：

```powershell
git --version
py -3.12 --version
cmake --version
rustc --version
cargo --version
rustup show active-toolchain

py -3.12 -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements-dev.txt
python -m pip check
```

如执行策略阻止激活，
可以直接用 `.\.venv\Scripts\python.exe` 替代所有 `python` 命令。
不要使用只会打开 Microsoft Store 的 `python` 别名。
另一个受支持的包安装位置是 `python -m pip install --target .tools/python -r requirements-dev.txt`；
共享脚本会把该目录加入 Python 搜索路径。新电脑优先使用独立虚拟环境，避免混用旧机器的包。

`requirements-dev.txt` 部分包使用版本区间，尚无完整 Python lock 文件；成功验证后先运行
`New-Item -ItemType Directory -Path .build -Force`，再用
`python -m pip freeze > .build/python-freeze.txt` 保存当次解析结果。

## 路径与运行环境

`tools/palmods.py` 和 `tools/paths.ps1` 管理路径。目前 UE4SS 相对游戏根目录的布局固定，
只设置游戏根目录不够时，需要把安装整理为下面的结构；没有单独的 `UE4SS_ROOT` 环境变量覆盖。

```text
<PALWORLD_ROOT>/
  Pal/Binaries/Win64/Palworld-Win64-Shipping.exe
  Mods/NativeMods/UE4SS/
    UE4SS.dll
    Mods/PalSchema/
```

```powershell
$env:PALWORLD_ROOT = 'G:/SteamLibrary/steamapps/common/Palworld'
$env:UNREAL_ROOT = 'D:/Epic Games/UE_5.1'
$env:REPAK = (Join-Path $PWD 'tools/bin/repak.exe')
# 默认为仓库 .build/PalCombo；通常不必设置
$env:PALCOMBO_BUILD = (Join-Path $PWD '.build/PalCombo')

Test-Path "$env:PALWORLD_ROOT/Pal/Binaries/Win64/Palworld-Win64-Shipping.exe"
Test-Path "$env:PALWORLD_ROOT/Mods/NativeMods/UE4SS/UE4SS.dll"
Test-Path "$env:UNREAL_ROOT/Engine/Binaries/Win64/UnrealEditor-Cmd.exe"
& $env:REPAK --version
& $env:REPAK pack --help
```

repak 必须支持打包器使用的 `--version V11 --compression Zlib`。
环境变量只对当前 PowerShell 会话及子进程生效，新终端需重新设置。

## 获取 UE4SS：公开源码与本机依赖的区别

新机器、`.tools/RE-UE4SS` 不存在时：

```powershell
.\tools/setup_ue4ss.ps1
git -C .tools/RE-UE4SS rev-parse HEAD
git -C .tools/RE-UE4SS submodule status --recursive
```

脚本克隆并固定提交，再初始化子模块。固定提交的 [.gitmodules](https://raw.githubusercontent.com/UE4SS-RE/RE-UE4SS/2281fa311e417b1dfddedbcd49972d764fddb244/.gitmodules)
列出 `deps/first/Unreal`（`Re-UE4SS/UEPseudo`）和 `deps/first/patternsleuth`，使用 GitHub SSH URL。
SSH 拉取需要 GitHub SSH 认证；Unreal 依赖还可能需要仓库访问资格，上游 README 提到 Epic／GitHub 账号关联。
本机历史记录中 Unreal 原 URL 无法获取，因此**目前不能承诺该命令在新账号／空机器上一定完成**。
`Permission denied (publickey)` 要检查 SSH；`Repository not found` 要检查 URL 和账号访问权，不能靠跳过子模块解决。

本机 `.tools/RE-UE4SS` 是迁移来的**无 `.git` 源码副本**，包含 Unreal 头文件和生成头文件。
它不是可用 `git rev-parse` 证明版本的 checkout；Git 会向上找到 PalMods 仓库，得到的是本仓库提交。
`setup_ue4ss.ps1` 现在会明确拒绝把这种目录当作固定版本 checkout。
要尝试官方获取，可用 `-DependencyDirectory .tools/RE-UE4SS-fresh` 保存到另一个空路径；
PalCombo 对应配置要额外传 `-DUE4SS_SOURCE=<该目录的绝对路径>`，BetterWorkbench 默认仍读取 `.tools/RE-UE4SS`。

SDK 首次 CMake 配置还会通过 FetchContent 获取第三方依赖，Rust 会下载 crates；需要 GitHub 和 crates.io 网络。
本机 SDK 的 `deps/third/CMakeLists.txt` 包含 glaze、GLFW／glad、ImGui／ImGuiColorTextEdit、
IconFontCppHeaders、Zydis、PolyHook2、raw_pdb、Corrosion、fmt、Tracy 等依赖。
其中有跟随 `main` 的依赖，现有上游配置并非完全锁定；离线迁移需要保存实际获取的源码及 Cargo 缓存。
不要通过关闭版本检查或使用任意新版 SDK 来声称兼容现有 UE4SS ABI。

## 离线回归

```powershell
python tools/test.py --skip-native
python tools/test.py
```

第一条运行 Lua／Schema 回归；第二条再配置、编译并运行 3 个独立 C++ 测试，输出到 `.build/tests/`。
测试不部署到游戏，也不构建 UE4SS 或气流编辑器模块。

## PalCombo 原生 DLL

完整 SDK 可用后，显式选择与后续 BetterWorkbench 一致的工具集：

```powershell
$env:VCToolsVersion = '14.44.35207'
.\mods/PalCombo/tools/configure_native.bat -A x64 -T version=14.44.35207
cmake --build .build/PalCombo --config Game__Shipping__Win64 --parallel 4 -- /p:VCToolsVersion=14.44.35207
```

也可运行 `build_native.bat -A x64 -T version=14.44.35207`；复用旧库时以上显式 MSBuild 参数更清楚。
正常输出包含 `.build/PalCombo/Game__Shipping__Win64/bin/PalComboFillerNative.dll` 和 `lib/UE4SS.lib`。
安装时 mod DLL 命名为 `Mods/PalCombo/dlls/main.dll`，Lua 和配置来自 `mods/PalCombo/mod/`。
不要把 SDK 编出来的所有 DLL 自动覆盖游戏运行库；需要核对目标 UE4SS 版本。

## BetterWorkbench 原生 DLL

先完成 PalCombo／SDK 构建，再补齐**独立 ABI 审核参考快照**。
源码 ZIP 不含子模块；此步骤只建立参考头文件，不能替代完整 SDK：

```powershell
$sdkRevision = '2281fa311e417b1dfddedbcd49972d764fddb244'
New-Item -ItemType Directory -Path .tools/sdk-2281fa31/source -Force | Out-Null
Invoke-WebRequest "https://github.com/UE4SS-RE/RE-UE4SS/archive/$sdkRevision.zip" -OutFile .tools/sdk-2281fa31/source.zip
Expand-Archive .tools/sdk-2281fa31/source.zip -DestinationPath .tools/sdk-2281fa31/source -Force

python mods/BetterWorkbench/tools/build_native.py --enable-readonly --toolset version=14.44.35207
python mods/BetterWorkbench/tools/audit_native_imports.py
```

构建脚本读取 SDK 的 `PalComboFillerNative.vcxproj` 中的 Shipping 编译／链接配置，
从游戏 EXE 生成字节保护，比较参考快照的头文件，然后生成并构建 `.build/BetterWorkbench/native/`。
`--enable-readonly` 是历史参数名，当前代码包含制作事务，不应据此理解为只读 mod。
输出为 `native/Release/BetterWorkbenchNative.dll`；审核还读取实际游戏目录的 `UE4SS.dll`，
生成 `.build/BetterWorkbench/import-audit.json`。

若 `.build/PalCombo` 缺少 Shipping `UE4SS.lib`，脚本回退读取 `.tools/ue4ss-sdk-cache`。
这是本机当前仍需要的旧库包，**不是可随意删除的缓存**。工程 XML 包含旧绝对路径，
脚本只处理其中一种历史路径；复制到新电脑不等于已经能链接。优先重建 SDK 并生成新 XML。

本机记录的游戏 SHA-256：`e590b5e7bfaa3fea40fab1a02cc72c8fc5fd6f8631ef2308e95ac56c25195837`；
审核记录的 UE4SS DLL SHA-256：`21b691a69a20c0801f465369d4fcbca7d7444764022fac2a7e8edc7709ef92b8`。
这些是已记录的二进制指纹，不是游戏下载链接或所有版本的兼容承诺。
可用 `Get-FileHash <文件> -Algorithm SHA256` 核对；游戏更新后脚本断言失败需要重新分析调用位置，不能删除断言绕过。

`deploy.ps1` 会检查审核哈希并修改游戏目录，须正常退出游戏后单独执行。
`package_candidate.ps1` 还要求 `.build/BetterWorkbench/validation.json` 与源码／DLL 匹配；
目前没有统一脚本从零生成该验证记录，因此仅编译和导入审核通过还不能直接打候选发布包。
可选 `check_cooked_recipes.py` 需要 UAssetAPI 格式的配方 JSON（默认 `.tools/game-data/recipes.json`）；
该游戏数据不在 Git 中，也不是普通 Lua 回归或 DLL 编译的必要输入。

## UpdraftElevator 编辑器资源、PAK 和 ZIP

安装 UE 5.1.1，设置 `UNREAL_ROOT` 和 `REPAK` 后按顺序执行：

```powershell
python mods/UpdraftElevator/tools/build_native.py
python mods/UpdraftElevator/tools/run_native_build.py
python mods/UpdraftElevator/tools/cook_native.py
python mods/UpdraftElevator/tools/package_native.py --stage-only
```

依次编译编辑器模块、从源码／贴图生成蓝图、Cook 为 Windows 资源、使用 repak 打包并校验。
`native/Content/` 没有提交，但由生成步骤创建；删掉它后不能直接跳到 Cook／打包。
`Source/Pal` 是编辑器使用的游戏 API 声明替身，游戏特效的占位资源由生成器创建；无需提取整套游戏资产。
生成物位于 `.build/UpdraftElevator/stage/`，发布包为 `dist/UpdraftElevator/UpdraftElevator-v9.zip`。
`--stage-only` 不安装到游戏；省略它会备份并安装，需游戏退出，且游戏内已安装兼容的 PalSchema／UE4SS。
进一步说明见 [气流原生构建](mods/UpdraftElevator/docs/NATIVE.md)。

六张 `assets/T_Wind*.png` 已提交，不必重生成。
只有运行 `generate_wind_art.py` 时才需要 numpy、Pillow 和 `C:/Windows/Fonts/bahnschrift.ttf` 字体文件。

## 换电脑需要保存什么，哪些可以重建

| 路径／内容 | 迁移或清理规则 |
| --- | --- |
| Git 中的源码、配置、Schema、源贴图 | 必须保留；新电脑 clone 即可获取 |
| `.tools/RE-UE4SS/` 完整源码，尤其 `deps/first/Unreal/` | 获取权限和从零构建未解决前必须备份；保留生成头文件及依赖来源记录 |
| `.tools/ue4ss-sdk-cache/` | 当前仍用于 SDK 编译配置和库；换机前整包备份，不能只留 `UE4SS.lib`，还链接 Unreal、Lua 和其他第三方库 |
| `.tools/sdk-2281fa31/source/` | 固定 ABI 参考快照，可用上面的源码 ZIP 步骤恢复 |
| `tools/bin/repak.exe`、游戏内 UE4SS／PalSchema | 不在 Git 中；保存可用版本、哈希和来源，或重新安装匹配版本 |
| `.tools/python/`、`.venv/`、`__pycache__/` | Python 环境／字节码可重建；优先在新机器重新安装 |
| Unreal `Binaries/`、`Intermediate/`、`Saved/`、`DerivedDataCache/`、生成的 `Content/` | 可按完整编辑器生成和 Cook 流程重建；删除后需要重跑对应步骤 |
| `.build/` | 混有编译产物、SDK 下载依赖、部署／资源备份和验证记录；不能整目录一律当垃圾；跨电脑的 CMake 工程应重新生成 |
| `dist/` | 发布包可以重打；正式发布过的版本按需归档 |
| `.local/` | 原本保存历史分析、旧 Git 元数据和备份；本机已按要求删除，历史文档中的相关路径仅为原始记录，不再代表文件仍可获取 |
| 游戏存档、BetterWorkbench `Jobs/`、玩家配置 | 用户数据，不能当缓存清理；Jobs 文件可能对应尚未完成的制作任务 |

迁移时同时记录 `git rev-parse HEAD`、Python 包解析版本、VS 工具集、Windows SDK、Rust、CMake、
UE／repak 版本和游戏／UE4SS 哈希。复制旧 SDK 仅提供恢复材料；只有在新路径重新编译 mod DLL、
通过离线回归和导入审核后，才能确认换机构建成功。游戏内兼容性、存档与联机仍需另行实测。
