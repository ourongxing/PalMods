# PalMods

三个 Palworld mod 的统一源码仓库。

| Mod | 功能 | 源码入口 |
| --- | --- | --- |
| [BetterWorkbench](BetterWorkbench/README.md) | 同工作台配方穿透、材料滚动、即时分解 | `BetterWorkbench/Mods`、`BetterWorkbench/Native` |
| [PalCombo](PalCombo/README.md) | 帕鲁按技能槽 1 → 2 连招，槽 3 填空 | `PalCombo/NativeSrc/MyCPPMods/PalComboFillerNative` |
| [UpdraftElevator](UpdraftElevator/README.md) | 三种尺寸的起跳升空气流建筑 | `UpdraftElevator/work` |

## 开发与测试

Python 3.12、CMake 3.22+、支持 C++20 的编译器；Windows 原生构建使用 VS 2022。

```powershell
python -m pip install -r requirements-dev.txt
python tools/test.py
# 只运行 Lua 与数据校验
python tools/test.py --skip-native
```

`tools/palmods.py` 统一管理 Lua 5.4 测试运行时、游戏目录、UE 编辑器、repak 和原生构建路径。
也可将 Python 依赖安装到根目录 `.tools/python`。离线测试不会部署到游戏。

本机路径可通过环境变量覆盖：

```powershell
$env:PALWORLD_ROOT = 'G:/SteamLibrary/steamapps/common/Palworld'
$env:UNREAL_ROOT = 'D:/Epic Games/UE_5.1'
$env:REPAK = 'D:/Tools/repak.exe'
# 默认指向本仓库的 PalCombo/NativeSrc/build
$env:PALCOMBO_BUILD = 'D:/Build/PalCombo'
```

## 原生依赖

```powershell
./tools/setup_ue4ss.ps1
./PalCombo/NativeSrc/build_mods_shipping.bat
python BetterWorkbench/tools/build_native_candidate.py --enable-readonly
```

UE4SS 统一固定到 `2281fa311e417b1dfddedbcd49972d764fddb244`，源码位于 `.tools/RE-UE4SS`。
BetterWorkbench 当前仍需 PalCombo 的 Shipping 构建所生成的 SDK 配置和库，
以及对应游戏二进制和本地 `.tools/sdk-2281fa31` 参考头文件快照进行 ABI 审核；详见其原生说明。
复用已有 SDK 编译缓存时，MSVC 版本须与库一致；可用 `--toolset version=14.44.35207`
指定本机已验证的工具链，并用 `--build-dir` 指定新的构建目录。
两个 mod 都有针对游戏版本的原生地址/结构校验，升级游戏后需重新验证。

气流资源构建需要 UE 5.1.1 和 [repak](https://github.com/trumank/repak)。
repak 默认放在 `tools/bin/repak.exe`，也可使用上述环境变量。
具体生成、Cook 和打包步骤见气流项目说明。

## 本地文件

只提交源码、配置、源贴图和测试。依赖、DLL、PAK、安装包、游戏数据导出、日志、
崩溃转储、Unreal 生成文件和安装备份均由 `.gitignore` 排除。
已弃用的气流脚本移入 `.local/retired/UpdraftElevator`；旧独立 Git 元数据移入
`.local/previous-git`，均只保留在本地。三个 mod 使用根目录唯一的 Git 仓库。

游戏内兼容性、存档与联机结果以各项目说明和实测为准；离线回归不代替游戏验证。
