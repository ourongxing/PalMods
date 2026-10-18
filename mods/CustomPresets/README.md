# Custom Presets 自定义预设

保存、切换和删除世界设置与人物外观预设。人物预设通过上半身缩略图选择，界面跟随游戏语言，支持中简、中繁、英、日。

## 使用

- 世界：在自定义设置底部操作。
- 人物：在人物编辑器的“预设”分类操作。
- 保存更新当前预设；新增时输入名称，允许同名。原版预设不可覆盖。
- 打开设置保留当前修改。人物名称和装备不保存，不新增外观选项。

## 安装与数据

订阅 [Steam 创意工坊](https://steamcommunity.com/sharedfiles/filedetails/?id=3822215387)，启用 UE4SSExperimentalPW 和 Custom Presets，然后重启游戏。

手动安装：解压 `dist/CustomPresets/CustomPresets-1.0.0.zip`，将 `CustomPresets/` 放入游戏的 `Mods/NativeMods/UE4SS/Mods/`，不要与 Workshop 副本同时使用。

数据位于 `%LOCALAPPDATA%/Pal/Saved/CustomPresets/presets/`：

- `world-N.preset` / `character-N.preset`：每个预设的名称和参数。
- `character-N.png`：人物缩略图。
- 相邻 `backups/`：写入备份与删除归档。

换电脑时复制预设目录，无自动云同步。

## 开发

```powershell
python tools/build.py CustomPresets
python mods/CustomPresets/tests/run.py
cmake -S . -B .build/tests
cmake --build .build/tests --config Release
ctest --test-dir .build/tests -C Release --output-on-failure
python tools/package_workshop.py CustomPresets --output-root dist/workshop-custom-presets-next
```

世界和人物结构超过旧版 UE4SS Lua 的 512 字节参数缓冲区，必须通过原生桥接刷新。桥接按反射参数大小分配内存并校验字段边界，缺失时禁止应用预设。

测试覆盖存储、编辑流程、语言、缩略图和原生参数处理。布局与手柄导航仍需游戏内验证。
