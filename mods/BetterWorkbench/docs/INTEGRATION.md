# 游戏接入契约

原生制作实现见 [NATIVE.md](NATIVE.md)，调用位置及布局见 [NATIVE_JOB_VIEW.md](NATIVE_JOB_VIEW.md)。

## 数据与权限

根配方和每个中间配方都须属于当前工作台的已解锁集合。已有中间材料可直接使用；
缺口仅展开为该工作台可制作的原料。配方 ID、产品 ID、产出数量和工作量分别保留。
静态表中的 `None` 材料槽忽略其数量，`DenyRecipeChain` 由游戏策略处理。

成本由原生研究方法提供，库存由当前请求的授权容器提供。容器／槽位身份去重，预览和提交分别读取新状态。
背包与基地的数值查询用于诊断；制作库存使用原生容器收集策略。

`Context.materialsForBatches(recipeId, copiedRow, batches, isRoot)` 返回该步骤整个批量的有效成本。
游戏快照设置 `RequireEffectiveCosts=true`；缺少成本提供器时返回 `effective_costs_unverified`。
多条配方产出同一物品时，在工作台集合中过滤并按 `PreferredRecipes` 选择。

## Lua 服务接口

`CraftService` 的后端契约用于预览和离线事务测试。`snapshot(context)` 返回拥有所有权的普通 Lua 数据：

```lua
{
    Inventory = { ItemId = 12 },
    Recipes = {
        RecipeId = {
            OutputItem = "ItemId", OutputAmount = 1, WorkAmount = 10,
            Materials = { RawItemId = 2 }, Expand = true,
        },
    },
    Context = {
        StationRecipes = { RecipeId = true },
        canCraft = function(recipeId, recipe, isRoot) ... end,
        RequireEffectiveCosts = true,
        materialsForBatches = function(recipeId, copiedRow, batches, isRoot) ... end,
    },
}
```

`transaction(context, buildPlan)` 在服务端读取最新配方、权限和库存，再执行一次求解及提交。
拒绝计划时保持库存和任务完整；失败时回滚已经发生的操作。客户端只提交配方 ID 和批数。
取消通过 `cancelNative(context, jobId)` 委托原生后端，返还记录取自实际投入。

## 反射与生命周期

- UFunction 已加载、参数布局和 delegate 状态核对后注册 Hook；`CALL`／`POST` 用于确认实际调用。
- Native post 回调参数顺序为 context、ReturnValue、原函数参数；Blueprint Hook 在执行后记录。
- `Setup.MatInfo` 的元素为 `PalStaticItemIdAndNum`：`StaticItemId` 是 Name，`Num` 是 Int。
- 已验证的 `TArray<FName>` 在同步回调内按有效索引复制；每次读取检查长度、容量和地址。
- UE4SS 的 `RemoteUnrealParam` 元素依赖原生缓冲区，输出数组／Map 在调用返回前完成复制。
- 数值计数方法要求 Static／BlueprintPure 标志及参数 Object、Name、Int64 返回；FName 构造器可为可调用 userdata。
- 诊断达到额度后停止读取参数。`MaterialAudit` 保持隔离，默认关闭诊断。

Hook 时机参考 [UE4SS RegisterHook](https://docs.ue4ss.com/dev/lua-api/global-functions/registerhook.html)。

## 本机实测依据

2026-10-06 的原版制作与只读桥接样本：

| 观察 | 结论 |
| --- | --- |
| 制作台 `GetRecipes` 返回 552 个 ID，含 CarbonFiber／CarbonFiber2，不含 Charcoal | 炉子木炭配方不属于制作台范围 |
| 1,414 条静态配方校验；部分 UI 材料数量小于静态需求 | 运行时有效成本须从原生方法取得 |
| CarbonFiber ×3：Coal 减少 6、FireOrgan 减少 3，领取增加 3 | 创建时取得整批材料，完成计数逐件推进 |
| Bio_Battery ×12 未完成即取消，三个材料各返还 12 | 原生取消返还实际未消费投入 |
| CarbonFiber ×27 从背包和基地取料，取消时材料返回玩家背包 | 退款目的地可与原来源容器不同 |
| 领取内部调用 Cancel_ServerInternal，剩余数为 0 | 领取清理与未完成取消须分别统计 |

原始桥接日志位于本机 `.tools/native-validation-20261006/`。

## 实机验收

- 现有中间材料、原料缺口、研究折扣和数量取整的 UI／服务器成本一致。
- 超过五种投入完整显示、转移和扣料；库存变化后提交重新计算或拒绝。
- 未解锁和跨工作台配方被排除，任务间的材料和进度独立。
- 部分完成后取消、满背包退款、领取、保存重载保持材料守恒。
- 动态槽位在重载存档后恢复，玩家与基地权限正确。
- 手柄、即时分解和其他配方／库存 mod 的组合单独验收。
