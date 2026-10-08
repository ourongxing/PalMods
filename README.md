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

## 测试

Python 3.12、CMake 3.22+、支持 C++20 的编译器；Windows 原生构建使用 VS 2022。

```powershell
python -m pip install -r requirements-dev.txt
python tools/test.py
python tools/test.py --skip-native
```

也可把 Python 依赖安装到根目录 `.tools/python`。测试不会部署到游戏。
`tools/palmods.py` 和 `tools/paths.ps1` 统一管理项目、构建及游戏路径。

```powershell
$env:PALWORLD_ROOT = 'G:/SteamLibrary/steamapps/common/Palworld'
$env:UNREAL_ROOT = 'D:/Epic Games/UE_5.1'
$env:REPAK = 'D:/Tools/repak.exe'
# 默认 .build/PalCombo；可覆盖为其他已构建 SDK 的目录
$env:PALCOMBO_BUILD = 'D:/Build/PalCombo'
```

## 原生构建

首次获取 SDK 执行 `tools/setup_ue4ss.ps1`；已有对应版本的源码副本时可直接构建。

```powershell
./tools/setup_ue4ss.ps1
# SDK 要求 MSVC 14.43+；本机默认较旧时选择已安装的新版本
$env:VCToolsVersion = '14.44.35207'
./mods/PalCombo/tools/build_native.bat
python mods/BetterWorkbench/tools/build_native.py --enable-readonly
python mods/BetterWorkbench/tools/audit_native_imports.py
```

UE4SS 固定到 `2281fa311e417b1dfddedbcd49972d764fddb244`，统一放在 `.tools/RE-UE4SS`。
BetterWorkbench 复用 PalCombo 的 Shipping SDK 配置及库；ABI 校验还需要本地
`.tools/sdk-2281fa31` 参考头文件快照和对应游戏二进制。
复用旧 SDK 缓存时编译器须匹配，可传 `--toolset version=14.44.35207`。
旧本机编译缓存保留在 `.tools/palcombo-sdk-cache`，只用于读取 SDK 配置与库。

气流资源构建使用 UE 5.1.1 和 [repak](https://github.com/trumank/repak)，
repak 默认位置为 `tools/bin/repak.exe`。完整命令见 [气流原生构建](mods/UpdraftElevator/docs/NATIVE.md)。

只提交源码、配置、源贴图与测试。旧独立目录的缓存和备份在 `.local/legacy-projects/`，
此前弃用代码和旧 Git 元数据也保留于 `.local/`；它们都不提交。
游戏内兼容性、存档与联机结果以各项目实测为准，离线回归不代替游戏验证。
