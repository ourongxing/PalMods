# 随处打开终端 / AnywherePalBox

UE4SS Lua Mod，版本 **1.0.0**。按 **K** 打开原版帕鲁终端，支持地下城。

- 据点内打开当前据点的终端。
- 野外或地下城打开自己公会建筑最多的据点终端；建筑数量相同则选择距离最近的据点。
- 每次按键重新选择据点；菜单打开、淡入淡出或玩家尚未就绪时忽略按键。

通过据点的终端模型调用原版交互，由游戏处理界面与关闭流程。

## 安装与卸载

退出游戏后运行：

```powershell
powershell -ExecutionPolicy Bypass -File mods/AnywherePalBox/install.ps1
```

脚本自动备份旧版、校验文件并启用加载。也可将
`dist/AnywherePalBox/AnywherePalBox-1.0.0.zip` 中的 `AnywherePalBox` 文件夹
解压至 `<Palworld>/Mods/NativeMods/UE4SS/Mods/`。

卸载时退出游戏，移除该文件夹及 `mods.txt` 中的 `AnywherePalBox` 加载条目。

## 快捷键设置

编辑安装目录下的 `AnywherePalBox/Scripts/config.lua`：

```lua
return {
    Hotkey = "K",
}
```

将 `K` 改成 UE4SS 按键名称，例如 `J` 或 `F6`，保存后重启游戏。
按键名称不区分大小写；配置缺失或无效时使用默认 K，并在 UE4SS 日志中提示。
安装脚本会保留已有配置。快捷键为单个按键，不支持组合键。

## Workshop 资料

`workshop/` 包含简体中文、繁体中文、日文和英文介绍、发布元数据及封面。
生成用于游戏 mod 管理发布的本地包：

```powershell
python tools/package_workshop.py AnywherePalBox --output-root dist/workshop-anywhere-palbox
```

打包工具校验安装目标并生成 ZIP 和文件哈希清单；不会上传或安装。

## 开发与验证

```powershell
python mods/AnywherePalBox/tests/run.py
python tools/build.py AnywherePalBox
```

回归检查覆盖快捷键配置、据点选择、所有权、重复按键和异常恢复，并核对本机游戏接口。
已确认游戏内可用，包括地下城；联机尚未验证。
