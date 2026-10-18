# Custom Presets 自定义预设

Workshop 本地测试版 1.0.0，依赖 UE4SSExperimentalPW，包含原生刷新与预览桥接 DLL。

## 使用

- 世界自定义设置下方提供预设切换、保存当前预设、添加为新预设和删除预设。
- 人物编辑器的“预设”分类下方显示自定义预设卡片，点击缩略图切换，卡片下方提供保存、新增和删除。
- 新增时使用游戏原生命名弹窗，默认名称为 `Custom Preset`。允许同名，不显示递增编号；需要改名时另存后删除旧预设。
- 原版预设只读。没有选中用户预设时，保存和删除隐藏并保留位置。
- 打开设置保留当前修改；只有手动选择预设或删除后选择相邻预设时才应用参数。删除优先选择上一个，其次下一个；删光时保留当前参数。
- 界面跟随游戏语言，支持简体中文、繁体中文、英语和日语，其他语言使用英语。用户名称不翻译，无悬停提示。

人物预设保存脸型、发型、身体类型、身体尺寸、头发／眉毛／皮肤／眼睛颜色、声音和颜色空间范围，不保存人物名称、装备、服装外观和存档身份。最终采用或取消外观仍使用游戏原本的按钮。修改已选人物预设后，标题显示“未保存修改”。

缩略图复用原版卡片，尺寸为 206×307，透明背景，构图为头部至腰部。保存或选用缺图预设后延迟截图；如果期间继续修改，则跳过截图，避免图片与已保存参数不一致。旧版图片在选用对应预设后重建，删除时归档当前图片。

## 安装与数据

当前测试包位于 `G:/SteamLibrary/steamapps/workshop/content/1623730/3621570584/`，仅本地测试，未公开发布。启动游戏后在 Mod 管理中确认 Custom Presets 与 UE4SSExperimentalPW 已启用。本机已切换到 Workshop 格式，避免再叠加手动安装副本。

独立开发调试仍可使用 `dist/CustomPresets/CustomPresets-1.0.0.zip`，将其中的 `CustomPresets/` 放到游戏的 `Mods/NativeMods/UE4SS/Mods/`。不要与 Workshop 安装同时使用两套副本。包内包含 `enabled.txt`，目录名保持 ASCII。

Workshop 版用户数据保存在 `%LOCALAPPDATA%/Pal/Saved/CustomPresets/presets/`，独立于安装目录。开发版迁移时应复制原安装目录的整个 `presets/` 到此目录。每个世界和人物预设分别保存为 `world-N.preset` 与 `character-N.preset`，单个文件包含名称和全部参数，无需额外索引。每个人物预设只保留一张 `character-N.png` 缩略图；内部唯一标识允许重名互不覆盖。预设文件和预览图的备份统一放在旁边的 `../backups/`，不堆积在预设主目录。安装包不包含用户预设、缩略图及备份。


## 开发与验证

```powershell
python tools/build.py CustomPresets
python mods/CustomPresets/tests/run.py
cmake -S . -B .build/tests
cmake --build .build/tests --config Release
ctest --test-dir .build/tests -C Release --output-on-failure
```

Lua 测试覆盖持久化、名称验证、重名隔离、世界／人物数据隔离、新增／保存／选择／删除、失败回滚、关闭后取消排队操作、原版预设保护、布局接口、语言切换、未保存提示和缩略图生命周期。原生测试覆盖 Lua 参数消费顺序及缩略图尺寸、透明度、颜色转换和上半身裁切。实际分辨率布局和手柄导航仍需游戏内验证。

世界和人物结构超过旧版 UE4SS Lua UFunction 的 512 字节参数缓冲区。桥接按运行时 `GetParmsSize()` 分配内存，校验反射签名和字段边界，并管理结构成员生命周期；缺少桥接时拒绝应用，不回退到不安全的大结构 Lua 调用。截图入口按 LuaMadeSimple 消费参数后的索引读取文件名，避免对已移除的参数取值。

## Workshop 本地测试

四语资料和封面位于 `workshop/`。使用 `python tools/package_workshop.py CustomPresets --output-root dist/workshop-custom-presets-next` 打包。当前仅本地测试，不创建或公开 Steam 条目。迁移目录见 `docs/WORKSHOP.md`。
