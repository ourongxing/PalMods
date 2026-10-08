# 游戏接入契约与证据

## 本机观察（2026-10-06）

用户指定安装目录：`G:\SteamLibrary\steamapps\common\Palworld`。

读取到的 `Mods/NativeMods/UE4SS/UE4SS.log` 时间为 2026-10-01，记载 UE4SS `v3.0.1 Beta #0`，Git SHA `2281fa31`。Steam `appmanifest_1623730.acf` 的 build ID 为 `25246127`；没有从这些数据猜测游戏的语义版本号。

本机已安装的 `AntiWasteDisassembleItems/Scripts/Core/core.lua` 使用以下接口／字段：

- `GetItemRecipeDataTableAccess(ctx.pawn)`
- `BP_FindRow(itemStaticId, isRecipeFound)`，通过 `isRecipeFound.bResult` 判断结果。
- `Product_Count`、`Material1_Id`／`Material1_Count` 到 `Material5_Id`／`Material5_Count`。

这只是已有 Mod 源码中的观察，BetterWorkbench 尚未在运行中的游戏验证这些接口。项目的 `RecipeNormalizer.fromFlat` 只做数据转换，不调用游戏。输出物品身份、工作量和有效折扣仍需由适配器明确提供。不要把网络示例的 `OutputAmount`／`Materials` JSON 字段当作当前原生结构体字段。

同一日志还含 `PalSchema` 的 `CraftItemCount_ApplyDataMapReturn` 签名查找失败。这不能说明 BetterWorkbench 接入必然失败，但说明不能直接依赖旧版本签名。

## 外部参考

- [UE4SS RegisterHook 文档](https://docs.ue4ss.com/dev/lua-api/global-functions/registerhook.html)：UFunction 必须已加载；`/Script/` 和 Blueprint 路径回调时机不同。返回 `nil` 保持原返回值，不能据此假设可以取消一个 void 服务器请求。
- [Tweaksmith 源码与说明](https://github.com/Worsthof/tweaksmith)：展示运行时全局修改配方表，不能证明独立 RecipeView 或原子扣料接口已存在。

## 适配器必须实现的职责

`PalworldAdapter.start` 当前仍返回制作适配不可用，同时启动只读诊断。诊断先从实际已加载的 UClass 枚举 UFunction，白名单命中且不是 delegate 才注册日志 hook；不把候选类名当作已验证接口。`HOOK` 日志仅证明注册，`CALL` 日志才证明调用路径。原子扣料与 UI 替换仍未完成。

1. 对当前游戏生成或取得反射／SDK 资料，观察打开工作台、选择配方、修改数量、点击制作、完成／取消任务时的真实调用链。记录准确函数路径、参数、执行端和有效生命周期。
2. 从游戏中读取有效配方快照，转换成 RecipeBook schema。根配方用 recipe ID，不能只按产物名称猜测；建立产物索引并处理重复配方。
3. 按原生制作的可访问范围统计真实库存，按容器／槽位身份去重，包含已预留数量；避免重复计算玩家背包和基地容器。Context 每次携带当前玩家、基地、工作台与授权状态，不使用全局“当前玩家”。
4. Hook 原生本次制作的材料视图、拥有数量、缺口和可制作判定。数量发生变化时重新求解。不要改全局 DataTable；若原生 UI 只有五行，不能静默截断超过五种材料的计划。验证是否可动态扩展原生列表，否则保留原生行为并禁用该计划。
5. 在服务器创建生产任务处调用 CraftService.commit。若现有 UFunction hook 无法在正确阶段拦截验证／扣料，使用经验证的 native C++ bridge。不要依靠不确定的 Lua 回调时机提交任务。
6. 累计工作量、输出数量、经验、取消行为、任务保存和读取都必须有明确处理。展示成功不代表交易已成功。

## 后端接口（项目自定义，不是游戏 API）

`backend:snapshot(context)` 返回独立的普通 Lua 数据：

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
        StationRecipes = { RecipeId = true }, -- 当前工作台的已验证配方集合
        canCraft = function(recipeId, recipe, isRoot)
            -- 已验证的科技／工作台／权限逻辑；返回 true 或 false, reason。
        end,
    },
}
```

`backend:transaction(context, buildPlan)` 必须在服务器执行一个完整事务：锁定或保留可用库存，读取最新配方和有效成本，调用 `buildPlan(state)` 一次。返回 `nil, reason, rejectedPlan` 时不扣料、不建任务；返回可制作计划时，一次性扣除 `Consumed` 并创建一个原生根产物任务。必须防止原生路径再扣一次原配方材料。任务失败、断连或持久化失败时不能留下半次提交；具体回滚能力需在 native bridge 中验证。

此事务能力没有在当前项目实现。离线模拟仅用来检验重新求解与拒绝旧预览的服务流程，不能替代服务器事务。接入 hook 的边界还需要捕获 Lua 错误，在产生副作用前完整退回原生行为；一旦开始扣料，不得继续触发原生制作作为兜底。

取消任务的返还材料必须来自实际扣料计划，不能从原配方重建。若原生任务不能保存 BetterWorkbench 成本，需可持久化的服务端附属数据；未验证前禁用这类提交。客户端预览完全不可信，服务器只接受配方标识与批数，并自行校验它们与玩家／工作台上下文。

## 实机验收

- 有足量中间材料时，UI／扣料与原配方一致；缺口时才显示下层原料。
- 数量增减能正确处理按批次取整；超过原生行数不漏显示、不漏扣料。
- 点击前库存被其他玩家使用后，重新计算或拒绝，没有材料变负或免费产出。
- 两名玩家、两个基地同时预览／提交互不污染。
- 科技未解锁或不可用工作台的中间材料不能穿透；已有中间库存仍按原生规则使用。
- 一个任务只扣一次，工作量包含展开步骤；完成、取消、保存、重载均保持成本与产出一致。
- 与研究折扣、配方修改、共享库存 Mod 组合时，UI 成本与服务器成本一致。
- 不支持的游戏版本保持入口无副作用，输出诊断信息。

## 本轮调试结果

2026-10-06 11:52:56，游戏新日志记录 `Starting Lua mod 'BetterWorkbench'` 及入口消息，首版实际加载已确认。更新的反射诊断需要再次启动游戏后读取新日志。

从本机 `Pal-Windows.pak` 提取并解码了原生制作模型、配方按钮和 `DT_ItemRecipeDataTable`。模型蓝图继承 `/Script/Pal.PalUIConvertItemModel`，自身没有 Blueprint 制作逻辑，关键流程在 native 类中。配方按钮蓝图引用 `CollectLocalPlayerControllableItemInfos`、`GetItemRecipeDataTableAccess` 与 `BP_FindRow`。这些已从资产静态确认，仍需实际调用日志确认其上下文和时机。

配方按钮 `Setup` 的 Blueprint 字节码把传入的 `MatInfo` 数组（元素字段 `StaticItemId`／`Num`）复制到按钮实例自己的 `MatMap`；`UpdateSufficient` 按这些 key 调用原生库存收集器并比较需求。这证明列表按钮的成本判定有实例级材料输入，值得作为 UI 接入入口继续验证；不能据此认定详情面板与服务器生产任务也使用同一份输入。

静态配方表实际字段为 `Product_Id`、`Product_Count`、`WorkAmount`、`MaterialN_Id/Count`，另有 `DenyRecipeChain` 等字段。`WorkAmount` 是原生工作量单位，不能直接标为秒。1,414 条配方通过离线校验。真实 `PalSphere_Mega` 制作两批时，已有一个 `CopperIngot`，另一个用两个 `CopperOre` 展开；总工作量为 4,000 原生单位。只有一个 `CopperOre` 时拒绝该计划。此验证使用模拟库存和允许全部配方的测试策略，不证明实际科技、工作台或运行时成本正确。

发现 `MissileBullet` 等配方的空 `None` 材料槽可能留有非零数量。Normalizer 已按物品标识忽略这些空槽，不再把它们视为非法材料。`DenyRecipeChain` 的原生语义尚未确认，游戏策略接入必须保留它，不能直接从静态配方启用生产穿透。

可执行 `python tools/check_cooked_recipes.py <UAssetAPI 导出的配方 JSON 路径>` 复查本机静态配方；提取的游戏资源位于被忽略的 `.tools` 目录，不作为 Mod 发行内容。

## 实际调用确认（2026-10-06 12:13）

诊断版已实际加载，五个目标类的反射枚举均完成，未记录 BetterWorkbench 的回调／注册错误。已捕获：

- 12:13:29，`PalUIConvertItemModel:Initialize(InModel)` 打开制作界面，传入真实 `PalMapObjectConvertItemModel`。
- 随后按钮 `Setup(RecipeID, MatInfo)` 与 `UpdateSufficient` 实际触发，包含 Arrow 等物品。
- 12:13:53，`PalMapObjectConvertItemModel:ChangeRecipe_ServerInternal(RequestPlayerId, Archive)` 实际触发。
- 12:13:56，`Cancel_ServerInternal(RequestPlayerId)` 触发前，模型为 `CurrentRecipeId=Salvage_TreasureBoxKey02`、`RequestedProductNum=56`。

这确认了 UI 到服务器配方任务的真实入口，并不证明扣料已拦截或穿透已生效。`ChangeRecipe_ServerInternal` 的请求载荷是 `PalNetArchive`，尚未解析；数量的语义也仍需核实，不能直接当作核心 `batches`。

本轮还确认 `PalUIConvertItemModel` 自身提供 `StartProduction`／`CanStartProduction`，先前候选的 `RequestStart` 未在它的直接函数列表出现。选中配方与材料覆盖字段不在这个类自身的属性中，因此更新诊断将继续沿真实的 Pal 原生父类枚举，并记录 native 函数前后状态。频繁 getter 每阶段最多记录三次，以保留日志额度给制作与取消事件。新版需要重启游戏加载；当前运行的旧诊断已完成上述入口确认。

## 材料诊断更新

12:17:32 日志已捕获 `StartProduction → ChangeRecipe_ServerInternal`，模型从无任务变为 `Shield_SF ×1`；取消后恢复空任务。12:18:57 建立 `CarbonFiber ×54`，12:19:06 的 `OnFinishWorkInServer` 逐次减少剩余数量；12:19:09 领取时剩余为零，并清空任务。

发现原诊断对有返回值的 native post 参数顺序标注错误：`BP_FindRow` 的 post 实际顺序为 `(context, ReturnValue, RowName, bResult)`，不是 `(context, RowName, bResult, ReturnValue)`。安装版本的 UE4SS 源码 `UE4SS/src/Mod/LuaMod.cpp` 也明确先推入 return 参数。已修正标签顺序，并测试在通用调用日志达到上限后仍能缓存配方数据。

新增 MaterialAudit 只读取数据，不修改材料／任务：

- 从实际 `BP_FindRow` 返回结构复制配方，从按钮 `Setup` 的 `MatInfo` 数组复制界面材料；再对照同一服务器任务的配方。
- 在 `ChangeRecipe_ServerInternal`、取消、领取、前两次生产完成的前后，各进行一次已加载 `PalItemSlot` 的有限扫描。读取 `ItemId.StaticId`、`StackCount` 和 `GetOuter` 所属对象；这些读法在本机已有 Mod 中出现，新增审计仍需实机验证。
- 按槽位地址去重，保留归属对象身份，报告每个槽位的变化及净变化。移入工作台缓冲区可能表现为原料转移而不是全局数量减少，需结合归属记录判断。
- 槽位缺失、新建、归属改变、读取失败或扫描上限均标为不完整／不确定，不假定它们就是消耗。全世界已加载槽位仅用于观察，不能拿来当基地／玩家的授权可用库存。
- 只审计本次启动中观察到创建的任务，最多 24 次操作；不持续扫描，也不自行重试制作或领取。

另加入 `PalItemUtility`、`PalItemSlot`、`PalItemContainer` 和 `PalNetArchive` 的真实反射枚举。原生库存收集器仅记录已有调用的结果，不由诊断主动调用。`PalNetArchive` 目前只检查字段定义，尚未解析或修改请求载荷。此更新尚待游戏重启后的实际 `AUDIT` 日志验证，生产穿透依然关闭。

## 崩溃回退与重载验证（2026-10-06）

12:24:38 的访问违规发生在启用自动重载之前。停用 BetterWorkbench 后用户确认启动正常；新增 MaterialAudit 及四个新增反射类、库存收集器钩子已撤回。上述材料诊断记录是历史实验，当前不接入游戏。`IsValid()` 对 UScriptStruct 只验证类型对象，不能保证 `start_of_struct` 数据地址可读；这是本机 UE4SS 源码确认的边界，不是崩溃位置的最终结论。Lua `pcall` 不能保护原生访问违规。

12:29:33 基本诊断加载。12:30:47 实际出现 `Auto-reloading Lua mod 'BetterWorkbench'`，随后输出 basic trace 入口标识，证明本次文件变更触发了自动重载。12:30:56 开始 `CarbonFiber2 ×2`，12:31:04 剩余数依次降为 1、0，领取后清空任务。12:31:12 开始 `CarbonFiber2 ×7`，12:31:13 在剩余数仍为 7 时取消，任务清空。用户确认本轮操作完成，无新增崩溃反馈。以上验证基本诊断运行，不证明真实扣料或取消返还正确。

离线校验新增实际根配方 `CarbonFiber2`：两批、已有木炭 1、木材 18、喷火器官 2，展开缺少的 9 个木炭，成本为已有木炭 1＋木材 18＋喷火器官 2，总工作量 29,000 原生单位。木炭足量时不展开；木材只有 17 时拒绝。库存与权限仍为模拟数据，尚未接入 UI 或服务器提交。

## 最新规则：禁止跨工作台

以上铜锭／木炭跨设施展开示例是历史实验，已被用户明确否决。只允许展开当前工作台自己能制作的中间配方，不能借用基地其他设施。`Context.StationRecipes` 必须来自该工作台原生可制作配方列表，且在提交时重新读取；列表未确认时拒绝计划。已有中间材料无需在当前工作台生产，可以使用；不足部分保持中间材料缺口，不展开为其他工作台原料。当前核心已强制此规则；原生配方列表安全读取尚未接入。

## 工作台配方范围诊断

新增 `StationScope.copyNames` 仅同步复制已验证的 `TArray<FName>` 返回值。12:41:02 自动重载后，游戏反射日志确认 `PalMapObjectConvertItemModel:GetRecipes` 的 `ReturnValue` 内层为 `NameProperty`。仅该 schema 允许读取，其他返回类型不枚举。长度最多 4,096，先检查容量，每次索引前确认长度未变化；索引始终限制在有效范围内（本机 UE4SS 在越界读取时也可能增长数组）。不使用本机源码中标有崩溃 TODO 的 TArray.ForEach，不读取配方结构体、不枚举世界槽位、不保留原生指针。`STATION_RECIPES` 是特定模型的日志样本，不能作为服务器提交的缓存依据；未来必须在提交时取得新鲜授权集合并额外校验科技及权限。28 项离线测试通过，实际返回列表仍待工作台打开事件验证。

配方选择补充：`RecipeBook:forOutput` 接受当前工作台配方集合，先过滤其他设施配方，再处理同物品多配方歧义。`PreferredRecipes` 指向其他设施时返回 `cross_station_recipe`，不能绕过限制。29 项离线测试通过（含 200 个守恒场景）及 1,414 条本机配方校验通过。新版工作台范围诊断和核心已部署，实际返回列表暂未出现；UI 与服务器扣料保持未接入。

12:43:23 实际捕获当前制作台 `GetRecipes` 返回的 552 条配方 ID（两次样本），包含 `CarbonFiber` 与 `CarbonFiber2`，不含 `Charcoal`。这是工作台排除炉子木炭配方的实机证据；不代表已验证科技、库存范围或扣料。读取后游戏继续运行，日志未见新增 BetterWorkbench 回调错误。

## 原版界面有效材料需求

12:46:21 自动重载后，真实反射确认 Setup.MatInfo 内层为 `PalStaticItemIdAndNum`，字段为 `NameProperty StaticItemId` 与 `IntProperty Num`。新增 `NativeMaterialView.copy` 仅在同步 Blueprint Setup 回调中按有效索引读取最多 64 个元素，核对结构名称、数据／属性映射和非空地址，再复制名称和数量；不使用 TArray.ForEach、不持有原生指针。旧 MaterialAudit 与全世界库存扫描仍未接入。

12:46:47 实际捕获 12 条 UI 材料需求，其中 4 条不同于静态配方：Bat 木材 5→4，Torch 木材／石头各 2→1，Bat3_4 精炼材料 35→33 与木材材料 52→49，Axe_Tier_00 木材／石头各 5→4。差异原因尚未确认，不假定一定来自研究折扣。UI 的 MatInfo 是界面需求而非可用库存；其批量与服务器舍入语义尚未验证，不直接用于扣料。可运行 `python tools/check_ui_costs.py` 复查并保存本机对照结果（不包含玩家 ID）。31 项离线测试通过；读取后未见新增 BetterWorkbench 回调错误，用户确认界面已打开。当前日志命中上限只记录前 12 个 Setup 样本，尚未取得碳纤维 UI 成本样本。

## 本地背包／基地数量诊断

新增 `NativeCounts` 核对实际存在的 `CountLocalPlayerInventoryItemNum64` 与 `CountLocalPlayerInsideBaseCampItemNum64`：参数必须按序为 ObjectProperty WorldContextObject、NameProperty StaticItemId、Int64Property ReturnValue，并具备 Static 与 BlueprintPure 标志。取得已验证类的 CDO 后，仅在有效 UI Setup 的同步游戏线程上下文中调用，最多 6 次采样、每次最多 8 个物品。使用数值返回而非槽位／材料返回结构，不挂钩原生库存收集器、不扫描世界槽位。两类结果分别记录，不假定范围不重叠、不相加，不作为服务器库存。发生读取异常后关闭查询且不将异常视为零库存。33 项离线测试通过，原生数量查询仍需实机采样验证。用户确认研究可降低需求，所有中间配方与根配方的有效成本都须在提交时由服务器重新确定；不能将 UI 单份需求直接假定为服务器批量成本。

12:51 初次启动数量查询被配置检查关闭，原因是当前 UE4SS 将 `FName` 构造器暴露为可调用 userdata，而非 function。已按本机 `LuaFName.cpp` 的 __call 实现修正，离线覆盖了可调用对象构造器。12:52:02 自动重载后实际输出 `COUNT_SCHEMA local player/base scalar queries verified`，两条查询的签名、Static/Pure 标志及 CDO 已核对成功。数量结果仍待工作台重新打开时的 `LOCAL_COUNTS` 验证。

## 已取得数量样本与批量减耗接口

12:53:11 实机 `LOCAL_COUNTS` 确认背包／基地数值查询有结果：木材 5390／0，石头 2216／0，喷火器官 7／53，生物电池 56／37，热能核心 5／283，毒腺 0／278。两列仍分别保留，不能据此断言原生可制作库存等于二者之和。日志未记录查询关闭或回调错误。

本机 recipe-slot 蓝图 `UpdateSufficient` 使用 `CollectLocalPlayerControllableItemInfos(self, MatMap.Keys, OutItemInfos, 2)`，不是上述两条数值查询。其库存策略尚待验证。检查当前 UE4SS 的 `LuaUObject.cpp` 后，直接调用该函数并传 Lua 输出表也不保证拥有数组元素：数组转换仍通过 `Operation::GetParam` 创建元素包装，结构数据依赖原生调用参数缓冲区，不能在函数返回后读取。没有新增库存收集器调用／钩子。

核心新增 `Context.materialsForBatches(recipeId, copiedRow, batches, isRoot)`。返回值是该步骤**整个批量**的有效成本 `{ ItemId = integer }`，由适配器按当前研究状态与原生舍入生成，不假定单份成本乘批数。根配方与每个实际展开的同工作台中间步骤分别查询；已有中间库存和跨工作台配方不查询中间成本。材料身份以当前配方快照为准，所有原材料必须显式提供数量，零成本必须明确写 `0`；漏项、额外材料、负数、小数或超限均拒绝。返回 `nil, reason` 表示尚未确认成本，不能用静态需求回退。

接入游戏的快照必须设置 `Context.RequireEffectiveCosts = true`；缺少提供器时返回 `effective_costs_unverified`。未设置此标志且没有提供器时的线性静态成本只供离线固定配方使用。`CraftService.commit` 仍从服务器事务内的新鲜状态重新调用提供器，预览结果不能授权扣料。新增测试覆盖根／中间不同批量舍入、成本缺失、工作台限制、非法结果与预览后研究变化。38 项离线测试及 1414 条本机配方校验通过；服务器成本提供器与原子扣料后端尚未接入，实际制作仍保持原版行为。

## 喷火器官界面总数核对

用户回复原版界面拥有数量为 60，与 12:53:11 的 `Arrow_Fire` 样本背包 7、基地 53 的和相符。记录为单物品／当次工作台的人工核对，尚不能扩展成所有物品与工作台的库存合并策略或服务器扣料授权。

进一步只读分析本机可执行文件的注册候选与调用链：库存收集函数 exec RVA `0x29806c0` 调用 `0x2fa0480`，再经 `0x2fa10d0`、`0x2fa0d00` 收集容器后由 `0x2fa0020` 聚合物品。在容器选择函数中，CollectType 0 与 2 执行第一分支，1 与 2 执行第二分支；结合两个已验证数值查询的调用链，第一分支对应本地玩家持有容器，第二分支涉及玩家所在基地。基地分支含额外条件调用（例如 RVA `0x3195250` 的返回值检查），聚合步骤也有物品／槽位筛选，因此尚未证明两条数值计数与原版制作收集器在所有状态下等价。

`CountLocalPlayerInventoryItemNum64` 的 exec RVA `0x2981060` 调用 `0x2fa3cb0`，从本地玩家关联对象执行独立计数；其错误字符串明确提示不能用于专用服务器。`CountLocalPlayerInsideBaseCampItemNum64` 的 exec RVA `0x2980f80` 调用 `0x2fa3930`，同样依赖本地玩家和基地上下文。以上地址只用于本机版本离线分析，没有注册地址钩子或在游戏中调用这些地址。继续保持两类数值分开，服务端适配必须另行确认授权容器、批量成本、扣料与取消返还。

## 碳纤维／生化电池专项采样

用户指定只通过碳纤维和生化电池继续测试。配置 `FocusRecipes` 为 CarbonFiber、CarbonFiber2、Bio_Battery，Setup 首先有限读取配方 FName，跳过其他配方的材料数组，避免前 12 个普通按钮用完材料采样额度；每次加载最多检查 600 个 Setup 配方 ID，达到上限后不再读取参数。两种碳纤维分支仍分别记录，不将当前选中的根配方擅自作为所有中间配方的偏好。

`FocusItems` 是两组配方涉及的 7 个材料／产物 ID：Coal、Charcoal、FireOrgan、ElectricOrgan、IronIngot、CarbonFiber、Bio_Battery。在已注册的原生 ChangeRecipe_ServerInternal、Cancel_ServerInternal、PickupProduct_ServerInternal 前后，同步调用已核对的数值计数，写 `FOCUS_COUNTS phase=CALL/POST`。仍不合并背包和基地数量，也不操作库存。每次加载最多 24 组数量查询，包含 Setup 数量样本；达到上限后停止。模型、事件、前后阶段和常规任务字段用于关联，不能将两次读数之间的所有变化自动归因于本次制作（其他生产／移动材料可能同时发生）。未增加库存收集器钩子或世界槽位扫描。

本机静态 Bio_Battery 配方材料为 ElectricOrgan 1、IronIngot 1、CarbonFiber 1；研究后的实际需求与批量舍入仍以本轮 UI 与制作日志为准。建议逐项进行：先碳纤维 3 个，完成并领取；再生化电池 3 个，完成并领取；最后每种开启 3 个，在完成前取消。保持工作台／基地相同并避免同时移动相关材料，有利于比较创建时扣料及取消返还。此次仅验证原版制作，不要求移空碳纤维库存，也不声称穿透已经启用。41 项离线测试通过，覆盖专项配方过滤不读取无关数组、采样额度、事件前后同步数值查询与停止后不访问参数。

## 13:01–13:02 专项制作结果与采样修正

本轮原版 UI 实际成本：CarbonFiber 为 Coal 2、FireOrgan 1；CarbonFiber2 为 Charcoal 5、FireOrgan 1；Bio_Battery 为 CarbonFiber 1、ElectricOrgan 1、IronIngot 1。当前研究状态下这些样本与静态材料需求一致，不代表其他配方或批量舍入已验证。

- 13:01:53 创建 CarbonFiber ×3 的原生请求前后，基地 Coal 3159→3153，背包 FireOrgan 7→4；任务 RequestedProductNum=3、RemainProductNum=3。观察到请求处理期间扣除煤炭 6、喷火器官 3。13:02:02 原生完成回调使剩余数 3→2→1→0；13:02:03 领取时背包 CarbonFiber 56→59。
- 13:02:10 创建 Bio_Battery ×3，背包 CarbonFiber 59→56、IronIngot 81→78，基地 ElectricOrgan 174→171。13:02:15 剩余数依次到零；13:02:16 领取时背包 Bio_Battery 56→59。
- 领取函数内部还会调用 Cancel_ServerInternal，此时 RemainProductNum=0，材料数量前后没有变化。这是领取后的任务清理，不能作为未完成取消返还的证据。未来任务审计必须区分嵌套清理和用户取消。
- 13:02:24 创建 CarbonFiber ×8，13:02:25 在剩余仍为 8 时取消；13:02:30 创建 Bio_Battery ×16，13:02:32 在剩余仍为 16 时取消。两次任务均清空，但此次 24 组数量额度已被重复 UI 查询和前两次完成／领取用尽，未捕获这两次请求／取消的材料数值，无法判定返还。

修正专项 UI 数量采样：每个关注配方仅采一次数量，重复 UI 重建仍记录材料成本，但不再消耗库存查询额度。专项最多 3 组 UI 数量样本；原定两次完整制作（含领取内嵌清理）和两次未完成取消共需 20 组事件样本，加起来 23 组，保持总上限 24 不变。测试覆盖重复 UI 成本更新仍可记录、数量仅查询一次；原生材料写入与穿透仍关闭。补测只需两种未完成取消，不要求重复已确认的完成／领取。

## 13:05 补测：未完成取消与返还去向

13:05:37 创建 Bio_Battery ×12，背包 ElectricOrgan 16→4、IronIngot 78→66、CarbonFiber 56→44，各扣 12，基地对应数量未变。13:05:38 在 RequestedProductNum=12、RemainProductNum=12 时取消，三个材料背包数恢复为 16、78、56，任务清空。此次未完成取消完整返还了观测到的输入材料，没有增加成品。

13:05:43 创建 CarbonFiber ×27：Coal 背包 16→0、基地 3137→3099（合计扣 54）；FireOrgan 背包 8→0、基地 49→30（合计扣 27）。13:05:44 在 RequestedProductNum=27、RemainProductNum=27 时取消，Coal 背包 0→54、FireOrgan 背包 0→27，基地数仍分别为 3099、30，任务清空，CarbonFiber 成品数未增加。合计输入库存恢复，但从基地取出的部分被退到玩家背包，未退回原基地容器。这是混合来源扣料与返还去向的本机样本，不能将取消定义为逐原槽位恢复。

以上表明这两次原版请求在开始时扣除整批材料，未完成取消返还对应投入。在今后的穿透任务中，取消不能简单沿根配方返还碳纤维；必须明确实际展开投入与剩余数量对应的退款记录，避免退款和材料生成不守恒。已完成部分取消、背包满时的返还去向、专用服务器库存权限以及其他研究成本仍未验证；此次没有修改制作行为或启用穿透。

## 实际投入退款契约与目标配方验证

新增纯逻辑 `CancellationPlan.forUnstarted(job)`，输入必须是后端保存的任务记录：JobId、Status（active）、TotalBatches、CompletedBatches 和 ActualDebits。ActualDebits 必须记录原子创建时真正扣掉的材料，不能接收客户端提交的退款材料，也不能用预览／当前配方重新计算。仅 CompletedBatches=0 时返回独立的 `{ JobId, Refund }` 数据；已结算任务、缺少记录、部分完成任务拒绝，非法数量报错。模块不自行给物品或取消原生任务。

`CraftService.cancel(context, jobId)` 将验证委托给自定义后端 `cancelTransaction(context, jobId, callback)`：后端校验归属，锁定任务与接收库存，从持久化记录读取进度和实际扣料，校验 ID，再将退款和任务清除作为一次事务结算；失败保持任务及记录，重试不能重复退款。原生取消也可能自行返还，所以不能把 Lua 给料与另一次原生 Cancel 拼接。这是待实现的后端契约，没有宣称 Palworld 存在该同名 API。

本机 1414 条静态配方校验补充 Bio_Battery ×3：已有 CarbonFiber 1，缺少 2；明确煤炭配方时额外耗 Coal 4、FireOrgan 2，木炭配方时额外耗 Charcoal 10、FireOrgan 2，两者均同时耗 ElectricOrgan 3、IronIngot 3。没有明确碳纤维候选偏好时拒绝歧义；已有碳纤维 3 时不需要偏好且不展开。木炭不足依然缺木炭，不借用炉子的 Wood 配方。模拟未开始任务取消只退已有碳纤维 1 及实际展开投入，不退 3 个碳纤维。数据为本机真实静态配方，库存／权限／扣料收据为离线模拟，不作为游戏有效成本或后端授权。

44 项离线测试通过，新增实际投入复制、部分退款拒绝、归属验证、结算失败后重试和重复取消不重复返还的模拟事务检查。本机只读调用链进一步确认 Cancel_ServerInternal 的 native exec RVA 0x29b8100 经 0x30058b0 最终调用与创建共用的 0x3005d80 worker（取消时传空配方、零数量及额外标志）。创建／取消不能作为两个互不关联的覆写点处理。调用链仅离线分析，未按地址安装钩子；原生 UI、保存／读档、部分完成退款与原子库存后端仍待接入。

## 最新设计约束：优先使用游戏已有方法

用户明确要求尽量不要自己计算，优先使用已有方法。这一约束优先于前文自定义退款后端设想。材料需求与研究修正、库存权限和统计、扣料、任务及取消返还以游戏原生实现为准；BetterWorkbench 仅增加库存优先的递归缺口展开、当前工作台限制和流程协调。展开需求合并／中间产出向上取整属于 Mod 必要逻辑，但不能自行猜研究百分比、批量舍入、容器权限或退款比例。静态线性计算仅是离线测试，不是游戏适配默认路径。

当前版本真实反射已发现：

- `/Script/Pal.PalItemUtility:GetProductItemRequiredMaterialInfos(WorldContextObject, OwnerConcreteModel, RecipeID, OutRequiredMaterialInfos)`。
- `/Script/Pal.PalItemUtility:GetProductItemRequiredMaterialInfoMap(WorldContextObject, OwnerConcreteModel, RecipeID, OutRequiredMaterialInfoMap)`。
- `/Script/Pal.PalMapObjectConvertItemModel:CalcRequiredAmount(BaseRequiredAmount)`，离线 native thunk 显示输入与返回为浮点。
- 原版按钮已有的 `CollectLocalPlayerControllableItemInfos`，以及已观察到原版创建、取消与领取方法。

上述材料需求方法没有制作数量参数，尚需确认如何进入原生批量路径，不能把其结果直接乘批数当作服务器成本。输出数组／Map 在当前 UE4SS 的转换中也使用 GetParam 包装元素，不能假设调用返回后的 Lua 输出表已经拥有所有元素数据；数组／Map 生命周期仍需同步桥接或验证，暂不新增这些调用。

`CraftService.cancel` 已移除 CancellationPlan 接入，直接委托 `backend:cancelNative(context, jobId)`，返回原生后端结果；没有原生后端时拒绝，不回退到 Lua 自行给料。该接口为项目契约，并非声称游戏存在同名 UFunction。后端必须确认原生取消记录包含展开后的真实投入；若仍沿根配方返还碳纤维，不能启用该穿透任务。`CancellationPlan` 保留为离线材料守恒参考。45 项测试通过，新增原生取消委托及无自定义回退的验证。当前实际制作仍原版行为。

## 直接反编译结果：原生材料与输入槽路径

按用户要求继续直接静态分析本机可执行文件，取得 Cutter v2.5.0 Windows 便携工具及随附 Rizin / rz-ghidra，放在本机临时工具目录，不改游戏文件。指定 x86 Sleigh 规范，仅分析已定位的函数，不执行全文件自动分析，也没有将地址安装为游戏钩子。导出的原始 Ghidra 伪代码在本机历史 `.local/legacy-projects/BetterWorkbench/.tools/decompiled-material-demand.c`、`.tools/decompiled-craft-worker.c`、`.tools/decompiled-refund-and-material-entry.c`、`.tools/decompiled-transfer-and-input-slots.c`，不随 Mod 分发。

| 本机 RVA | 静态分析确认的关系 |
| --- | --- |
| 0x2981670 | GetProductItemRequiredMaterialInfos 的 exec 参数封装，调用 0x2fadaa0。名称由真实反射与注册候选对应，并沿参数封装核对。 |
| 0x2fadaa0 | 根据配方生成材料数组，再取得所属工作台的修正并对各项执行原生数值转换、最少 1 的限制。不是最终批量请求。 |
| 0x3005d80 | 创建／取消共用 worker；创建分支直接调用 0x2fadaa0，再把每项数量乘请求批数，收集授权容器、聚合库存、检查材料数量，随后处理任务与输入槽。 |
| 0x3008ea0 | 遍历授权容器和材料项，按当前配方材料身份找工作台输入槽，通过原生操作及 0x3004ac0 回调处理实际转移。 |
| 0x300d010 | 取得工作台输入容器并明确枚举 5 个输入槽；这是一项原生容量限制，不能只更新 UI 列表后忽略它。 |
| 0x3023e70 | 更新输入槽时读取当前配方；配方为空的分支遍历实际槽位并进入原生清理函数 0x2fc6df0。与取消前先清空配方的 worker 路径、已观察到的材料返还相吻合。 |

关键修正：原生 worker **直接调用** 0x2fadaa0，不是通过公开 UFunction 的 ProcessEvent 执行。因此对 GetProductItemRequiredMaterialInfos 注册普通 Lua RegisterHook，不能据此覆盖服务器内部的成本计算。后续优先在 C++ 原生层对同一函数的材料输出做有限接入，保留它原本的研究修正，并让每个原生步骤自己处理批量；不能把 Lua 接口注册成功当成服务器覆盖成功。

同时，仅替换需求数组还不够：原生材料转移会按当前配方的材料 ID 顺序找输入槽。必须使该任务的配方材料视图、需求数组与槽位身份对应一致；禁止改全局原配方来同步它们。目标 Bio_Battery 的单一碳纤维候选展开：无已有碳纤维时 4 类材料，有部分已有碳纤维时 5 类材料，数量上可容纳于五槽，但混合成本的逐批消耗、任务保存／读档仍需沿原生完成路径确认。超出五类时不能静默截断。

原生取消在空配方分支清理实际输入槽，说明可优先复用真实槽位材料的返还，避免自行按根配方生成退款；原生清理函数的完整容器／掉落去向仍需追踪，不能把反编译伪代码当成已验证 ABI。Ghidra 输出有重叠变量、未知类型和未映射变量提示，函数名／参数类型由反射、封装汇编及调用现场交叉判断，不能直接把伪代码签名编译成 detour。本轮只做静态分析，无新增游戏行为或用户操作要求。

## 原生完成消耗路径与批量限制（2026-10-06）

进一步静态分析确认，原版每完成一件调用的是独立材料数量表函数 0x2fad860，而非已实机验证的需求数组函数 0x2fadaa0。完成流程位于 0x3012d70：按前五个输入槽实际物品 ID 查表，建立消耗请求，并通过 0x2fbc2f0 原生物品事务处理消耗和产出。部分已有中间件的批量计划不能表示为整数单件成本乘以请求数；必须分别接入整批校验、逐件消耗和任务材料视图。完整依据、调用位置和接入约束见 [NATIVE_JOB_VIEW.md](NATIVE_JOB_VIEW.md)。本轮无新 DLL 部署，当前只读桥接保持原样。
