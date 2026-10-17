# 快速肢解（Quick Butcher）

1.0.0 · ourongxing

第一个功能：使用切肉刀肢解帕鲁时，跳过玩家的肢解动画，进入原版的肢解结束流程。
仍从原版肢解入口操作，沿用目标检查、服务端结算、掉落、肢解次数记录与角色状态恢复。
原版结束流程中的延迟仍保留，因此不保证材料在点击后立刻到账。

## 安装

[Steam 创意工坊](https://steamcommunity.com/sharedfiles/filedetails/?id=3821569615)

订阅后在游戏模组管理中启用，完全退出并重启游戏。无前置 mod。

## 构建与开发测试

在仓库根目录执行：

```powershell
python tools/build.py QuickButcher
python mods/QuickButcher/tests/run.py
```

修改前完全退出游戏。发布后的开发测试使用工坊目录：
`G:/SteamLibrary/steamapps/workshop/content/1623730/3821569615/`。
将构建的 PAK 放入该目录的 `Paks/`，保留 `.workshop.json`；本地测试可将 `Info.json.DebugMode`
设为 `true`，使游戏每次启动重新安装。正式发布的模板保持 `false`。

产物：`dist/QuickButcher/QuickButcher-1.0.0.zip`；单独的 PAK 和 `build-audit.json` 也保存在该目录。
ZIP 与 `install.ps1` 用于独立手动安装，勿与工坊副本同时加载。

## 工坊资料

`workshop/` 保存工坊元数据、封面和简体中文／繁體中文／日本語／English 四语介绍。
首次工坊版本为 `1.0.0`，PublishedId 为 `3821569615`。游戏内功能验收仍待完成。
功能介绍只编辑四份本地化 README；反馈与开源部分由 `tools/workshop/templates/` 的四语公共模板自动追加，
`listing.json` 由统一打包工具生成：

```powershell
python tools/package_workshop.py QuickButcher --listings-only --output-root dist/quickbutcher-listings-next
python tools/package_workshop.py QuickButcher --output-root dist/quickbutcher-workshop-next
```

输出目录已存在时请指定新目录。工坊包使用 `Paks` 规则，将 `Paks/` 的内容安装到
`Pal/Content/Paks/~WorkshopMods/QuickButcher/`，无前置依赖。
切换到工坊验收时，先移除旧的 `~mods/QuickButcher/QuickButcher_P.pak` 手动副本，避免重复加载。
打包命令仅生成本地包；更新工坊时沿用现有 PublishedId。

## 实现与兼容

构建工具从本机游戏提取 `BP_ActionCutPalMeat_Player`，校验两个资产文件的完整 SHA-256，
仅将开始动作的动画分支续接地址改为原版完成分支。`.uasset` 保持原样，`.uexp` 只改一个四字节地址中的两个字节。
没有改写掉落数量或自行调用发奖／删除接口。资产版本不匹配时拒绝构建，需重新分析。

这是对原版动作蓝图的覆盖，与其他修改同一蓝图的 PAK mod 不兼容。
源码只保存补丁逻辑与校验值，不保存游戏原始资产。

## 验证

静态流程检查及打包往返校验可验证补丁范围和分支衔接，不能代替游戏内验收。
请用可丢弃的帕鲁确认：玩家不播放肢解动画、帕鲁只移除一次、材料只结算一次，
操作后移动／跳跃／切换武器正常，连续肢解正常。
联机模式还需分别验证主机与客户端；当前未确认联机效果。
