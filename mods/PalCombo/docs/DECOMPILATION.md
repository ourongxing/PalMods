# Palworld 技能选择调用链

2026-09-29 本机静态分析，游戏 EXE SHA-256：
`e590b5e7bfaa3fea40fab1a02cc72c8fc5fd6f8631ef2308e95ac56c25195837`。
下列地址均为该二进制的 RVA。

## 分析工具与资产

用 repak 从 `Pal-Windows.pak` 提取 `BP_AIAction_CombatPal` 和 `BP_MonsterAIController_Otomo`，
用 UAssetAPI v1.1.0 及 Palworld mapping 解码字节码，`tools/print_blueprint.ps1` 显示解码函数。
原生调用位置由 Rizin 反汇编取得。

## 普通战斗与玩家帕鲁

普通 `BP_AIAction_CombatPal` 的 `Get Next Action Slot ID` 调用
`UPalActiveSkillSlot::FindSlotIDForWildPal(TargetActor, empty ignore list)`，再选择 Waza 类并施放。

玩家控制器 `BP_MonsterAIController_Otomo` 的 `CombatModuleClass` 为 `PalAICombatModule_Otomo`。
`AttackForEnemy` 调用原生 `Set Combat Action And Target`，使用继承自 `UPalAIActionCombatBase` 的
`UPalAIActionCombat_Standard`。

## 原生动作链

| RVA | 行为 |
| --- | --- |
| `0x281ff20` | StartNextAction_Event 的 UFunction thunk，调用 `0x2d102c0` |
| `0x2d10336` | 尾跳到 ChangeNextAction `0x2cf6fc0` |
| `0x2cf7040` | 直接调用选择器 `0x2cfabb0`，参数为 slot、target、空 ignored-Waza-ID 数组 |
| `0x2cf708c` | 返回值 EAX 不为 -1 时写入 NextWazaSlotIndex 并解析 Waza 类 |
| `0x2cf7158`、`0x2cf7162` | 设置 NextIsWaza 和 NextActionClass |

返回 -1 时跳过 Waza 查询，继续动作类／嘲讽路径；已有缓存动作类也可能影响结果。

公开 `FindMostEffectiveSlotID` thunk `0x2815ac0` 经包装 `0x2cfab70` 调用同一选择器，
实际玩家战斗直接调用核心函数，因此 UFunction Hook 无法观察这条战斗路径。
普通 Blueprint 使用的 `FindSlotIDForWildPal` 对应另一个核心函数 `0x2cfb970`。

## 冷却接口与 Hook

| 接口 | thunk / native RVA | 返回 |
| --- | --- | --- |
| GetCoolTime | `0x2815e10` / `0x2cfcf70` | 已流逝冷却时间 |
| GetCoolTimeRate | `0x2815eb0` / `0x2cfd110` | 已流逝时间／总冷却时间 |

模块在 `0x2cfabb0` 安装 x64 detour，先调用原选择器，再为 `MonsterAIController_Otomo` 替换槽结果。
安装前验证 15 字节入口及 `0x2cf7040` 的直接调用。连招状态逻辑见 [DEVELOPMENT.md](DEVELOPMENT.md)。

早期游戏日志确认 detour 安装及 GrimGirl 的选择／施放 0→1→2；三槽不可用时仍观察到 GravityShot。
这支持原生 Hook 和备用动作路径；当前连招效果需结合实机施放日志核对。
