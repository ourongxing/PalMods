# 即时分解

点击工作台详情右上角已有成品数量，切换生产／分解模式。
库存足够一批时可进入分解；用原数量选择器选择批数，再按“开始分解”确认。
再次点击已有数量、选择其他条目或关闭工作台可退出分解。

## 材料与库存

按选中的配方 ID 计算：每批消耗 `OutputAmount` 个成品，返还原始 `Materials`，材料全部进入玩家背包。
例如每批产出两个成品、库存七个时，最多分解三批，保留一个成品。批数上限为 256。

成品先从玩家库存取，再从当前工作台基地的已解析容器取。可用总数须与
`CollectLocalPlayerControllableItemInfos(..., 2)` 一致。按静态物品 ID 和槽顺序取料，同 ID 的品质／耐久无法分别选择。

`DisassemblyCapacity` 为全部返还材料共同试算背包容量，要求普通可堆叠物品及已知最大堆叠数。
返还先于成品扣除，成品槽仍占用容量。背包不足、未知容器、权限或数量不一致时拒绝。

提交重新读取配方、范围和库存。`DisassemblyRuntime` 调用玩家库存的 `AddItem_ServerInternal` 返还材料，
核对实际数量，再减少成品槽 `StackCount` 并触发更新。写入异常时尝试恢复原槽数量，并关闭本次运行的分解。
原生添加失败可能产生世界掉落，背包回滚无法撤销掉落；此路径尚非原子事务。

当前支持单人／房主本机。客户端和专用服务器远程请求协议尚未实现。

## UI 与手柄

入口位于 `CanvasPanel_ItemNum`，横向拉伸、左右偏移为零；外层高度 28、垂直居中、关闭自动尺寸。
内部隐形按钮保留点击与焦点行为，文字、装饰和外扩边距清除，焦点框贴合已有数量。

配方列表向右到入口，入口向左回配方、向下到确认按钮，确认按钮向上回入口。
手柄选中条目后，用户焦点交给可用确认按钮，其次为分解入口，再次为数量区域。
`WBP_PalInvisibleButton` 启用聚焦、原生确认动作与焦点光标；鼠标选择保持自身焦点。
`InputMethodChanged` 后置钩子恢复摇杆导航，十字键继续控制数量。

分解模式将当前模型 `CanStartProduction` 返回值设为非成功值 1，阻止原生产请求；
`StartProduce` 的 Blueprint 后置钩子调用分解后端。进入模式前验证该保护，失败则退出。
标题显示每批产出，`nowNum` 表示批数，`GroupCount` 用于数量显示。

分解后通过 `OnClickedRecipeSlot` 刷新库存并保留当前模式。成品耗尽时批数为零、返还预览清空、确认禁用。
成功时保留原生获得物品提示并记录日志；失败使用 `PalUtility:Alert`，通知失败不重试事务。

当前工作台通过 Blueprint 字段 `Convert Item Model` 的 `TryGetConcreteModel(Model)` 取得，再读取 `GetRecipes`。
数组元素兼容 `RemoteUnrealParam`；Lua 重载时为已打开的工作台补挂入口。

## 原生接口

已通过本机反射核对：

| 函数 | 参数顺序 | 返回 |
| --- | --- | --- |
| `PalPlayerInventoryData:AddItem_ServerInternal` | StaticItemId (Name), Count (Int), IsAssignPassive (Bool), LogDelay (Float), bNotifyLog (Bool) | Enum |
| `PalNetworkPlayerComponent:RequestAddItem_ToServer` | StaticItemId (Name), Count (Int), IsAssignPassive (Bool) | 无 |
| `PalPlayerInventoryData:TryGetContainerIdFromItemType` | ItemTypeA (Enum), OutContainerId (PalContainerId) | Bool |
| `PalNetworkPlayerComponent:RequestMoveItemToInventoryFromContainer` | fromContainer (Object), IsTryEquip (Bool) | 无 |

`AddItem_ServerInternal` 的 exec 调用 `0x317b260`，再调用 `0x317abc0`。
上层 Enum 返回不能证明物品全部进入背包，须核对实际库存。
静态分析的事务候选：

| RVA | 作用 |
| --- | --- |
| `0x2fbc7c0` | 单种添加包装 |
| `0x2fc0ff0` | 添加／移除的共用准备路径，移除准备先于添加检查 |
| `0x2fc1400` | 验证输入与目标槽，按 0x58 步长遍历添加记录并生成操作清单 |
| `0x2fb5680` | 应用操作清单并触发容器更新 |

候选路径的完整 ABI 和失败清理待核实，当前 Lua 后端使用上层添加方法。

## 验收

入口点击和模式阻止原生产已有游戏日志确认；库存扣除、返还、手柄导航及存档持久化待验收。
先分解一批，核对成品减少量和各材料增加量，再检查整批产出、全部分解、满背包拒绝、重开界面及保存重载。
