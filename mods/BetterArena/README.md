# Better Arena / 更好的竞技场

1.0.0 · ourongxing

竞技场主菜单选择“扫荡”，再选择已通关的难度，立即获得该档重复通关奖励和胜利 RP。每档分别首通解锁，普通挑战入口保留。领取时播放原生奖励动画与音效，显示实际道具数量和 RP。

玩家积分段位决定每日次数：青铜至传奇分别为 **1 / 3 / 5 / 7 / 9 / 11 / 13 次**。所有难度共用，按游戏内天数刷新，不累计；当天升段补足额度差值。

普通 NPC 挑战与扫荡默认两倍物品和胜利基础积分，覆盖首通与重复通关。积分保留原版段位差计算，不改变掉落概率、失败扣分或 PVP 积分。

## 配置

编辑游戏目录中的 `Mods/NativeMods/UE4SS/Mods/BetterArena/Scripts/config.lua`，保存后完整重启：

- `RewardMultiplier = 2`：奖励倍率，限 1～10 的整数；1 为原版基础奖励。
- `DailyLimits = {1, 3, 5, 7, 9, 11, 13}`：青铜至传奇的每日次数，各项限 0～100。

进入世界后自动生成 PalSchema 补丁，核对奖励生效后开放扫荡。首次发现 PalSchema 自动重载关闭时会开启该设置，需再完整重启一次；此开关也适用于其他 PalSchema Mod。

## 依赖与范围

需要 UE4SS Experimental (Palworld) 和 PalSchema，支持单机及本机房主角色。联机客户端、专用服务器不支持，手柄导航未验收。界面支持简繁中文、日语和英语。

补丁以 Palworld 1.0.5 原版数据为基准，覆盖竞技场奖励表和 NPC 胜利基础分，与修改相同数据的 Mod 可能冲突。

次数记录位于 `%LOCALAPPDATA%/Pal/Saved/BetterArena/`，按世界和玩家隔离，备份存档时一并保留。背包不足时不结算；领取中断或数据损坏时停止重试以免重复发奖。游戏存档和额度分别保存，回档不会退还次数。

## 开发与验证

仓库根目录运行 `python tools/build.py BetterArena` 构建，`python mods/BetterArena/tests/run.py` 测试。关闭游戏后用 `mods/BetterArena/tools/install_local.ps1` 安装；默认保留当前配置，`-ResetConfig` 恢复默认值。

已发布至[创意工坊](https://steamcommunity.com/sharedfiles/filedetails/?id=3822475613)，四语资料在 `workshop/`。功能与倍率切换的实机证据、未验收范围见 [验收记录](docs/VALIDATION.md)。
