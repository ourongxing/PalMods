# better workbench（更好的工作台）

模组名称为 **better workbench / 更好的工作台**，安装目录和内部模块统一使用 `BetterWorkbench`。源码采用仓库统一布局：`mod/` 为部署文件，`native/` 为 C++，`tests/` 为全部回归，`tools/` 和 `docs/` 分别为工具与文档。部署时迁移旧 `SmartRecipe`、`SmartRecipeNative` 目录中的 Jobs 并备份旧目录，加载配置改为 `BetterWorkbench : 1`。新任务使用 `BWJ_` 标识和 `.bwj` 文件；旧 `SRJ_` 任务及 `.srj` 文件仍可恢复。本文历史记录中的名称已随项目更名更新。

即时分解：点击工作台详情右上角的已有成品数量，在生产／分解模式间切换。按完整配方批次立即消耗成品，原始材料全额返还到玩家背包，不排生产任务；支持玩家背包和当前工作台基地的成品库存。当前仅支持单人／房主本机，游戏内库存、手柄操作和保存恢复仍待验收。使用限制与验收步骤见 [即时分解说明](docs/DISASSEMBLY.md)，可通过 `Disassembly.Enabled` 关闭。

统一安装：Lua 脚本位于 `Mods/BetterWorkbench/Scripts`，原生核心位于 `Mods/BetterWorkbench/dlls/main.dll`，`mods.txt` 只需 `BetterWorkbench : 1`。`tools/deploy.ps1` 部署完整模组；更新前正常保存并退出游戏。旧 `SmartRecipe/Jobs`、`SmartRecipeNative/Jobs` 自动迁移到 `BetterWorkbench/Jobs` 并核对哈希，旧目录移到项目备份中，避免重复加载；同名任务定义冲突时停止迁移。原生日志中的 `[BetterWorkbenchNative]` 仅是内部组件标识。

材料 UI 滚动：原版工作台详情的 VerticalBox_TechDetails 保留原生材料行，外包 UMG ScrollBox 和限高 SizeBox。默认按前 5 行的实际期望高度及槽位上下间距计算可视高度，更多材料可用滚轮查看；保留原图标、名称、拥有／需求数量和不足颜色，以及同面板其他子控件的顺序和布局。只在原版 SetDetails 刷新后处理并更新高度，不新增轮询。配置 MaterialScroll 可关闭或调整 VisibleRows；RowHeight 仅在行期望高度尚不可用时作为后备值。实机日志已确认八行列表成功挂载滚动控件；本次按实际行高计算的布局仍待实机确认。使用现有 0.6.2 扣料 DLL，Lua 可自动重载。

0.6.2 修复实际完成制作仍只收集五槽扣料记录的问题。将整个单位计划的扣料记录一次性交给原生制作事务，保持原生产出、权限、事件和材料移除方法；不再只扣前五槽，也不执行额外的第二次扣料。制作完成前检查所有投入槽的身份和数量，不满足则阻止本次完成。日志 DEBIT / DEBIT_RESULT 记录各材料的实际槽位前后数量，最多 24 次正常完成。AIcore 八种材料和稀疏后续单位的回归通过；实机扣料尚待部署验证。

0.6.1 修复 0.6.0 在实际制作时的原生数组构造 ABI 错误：输入槽／输入索引函数接收未初始化的返回存储，Hook 必须先初始化为空数组，不能读取或释放旧字段。崩溃证据为 FMallocBinned2 非法块断言，发生在原生 0x3023e70 输入槽数组清理路径。材料身份枚举仍保留原生追加语义。修复版的实机制作、退款和保存恢复仍待验证。

当前实验包为 0.6.0-dynamic-inputs：已根据实机容器与本机反编译实现原生输入扩容。已验证类型的容器最多支持 64 种实际投入，固定保留索引 5 的成品槽；第六种投入从索引 6 开始。规划保持已有中间件优先，材料身份列表、实际输入槽和退款列表按同一计划对应。原版界面显示完整需求。编译与离线测试不代表游戏内扩容、取消退款和保存恢复已验收。

0.5.1：修正“部分现有中间件 + 展开原料”超过五槽导致整份计划退回原版的问题。保持库存优先；只有完整计划超过五槽时，尝试留下现有中间件、使用同工作台原料制作整份需求。原料不足时仍拒绝制作，预览显示真实缺口。电脑回归覆盖零碳纤维、部分库存、库存足够、原料不足和重复查询；日志单独保留 Computer 的成本／库存／失败原因，不受其他配方抢占额度。

0.5.0：穿透预览、实际制作和任务恢复均不再限制为碳纤维／生化电池。配方范围直接来自当前工作台的原生 `GetRecipes`，仅允许同一工作台且已解锁的中间配方；成本与研究减免继续调用原生方法。原版界面显示单批或当前数量的精确材料需求。

0.4.2 的运行时库存／数量／名称缓存已撤回，Lua 后台诊断默认关闭。每次请求按根配方筛选依赖，只查询相关材料的库存；不将其他配方、其他工作台或未解锁配方合并到生产范围。0.5.0 实机行为尚待验证，不能把离线测试视为游戏内验收。

每个穿透任务使用独立虚拟配方和不可变 Jobs 定义；进度保存沿用原生任务字段。详见 [docs/NATIVE.md](docs/NATIVE.md)。安装／更新 C++ DLL 后需要重启游戏。

当前限制：最多 256 批；验证通过的原生容器最多 64 种实际投入，其他容器保留五槽后备策略。仍不跨工作台。工时沿用根配方原生工时；多人 Jobs 定义同步及展开中间件的额外工时尚未完成。

## 已实现

- 递归展开缺失的中间材料，先消耗现有库存。
- 一个求解过程共用虚拟库存，避免多个分支重复使用同一份原料。
- 支持 `OutputAmount`、多批制作和中间产物按批次向上取整；同一计划内部可复用余量。
- 保留原配方，独立返回本次 `ResolvedRecipe`，包含材料、缺口、步骤和累计工作量。
- 检查循环、深度、节点数、数量上限和无原料配方；多条配方产出同一物品时要求明确选择。
- 制作服务在提交时重新读取服务器状态，不信任 UI 预览中的材料清单。
- 74 个离线测试，含 200 组材料守恒检查；覆盖原生快照拒绝、研究成本输入、混合逐件消耗、部分完成后恢复、新存档检查点、重复事务／错存档拒绝，以及即时分解的整批返还、背包容量、基地库存和 UI 切换。事务和保存恢复使用模拟原生状态，不能证明游戏内扣料或存档正确。
- 本机游戏包的 1,414 条静态配方已通过核心数据校验；用真实 `PalSphere_Mega`／`CopperIngot` 配方验证部分中间库存的展开和原料不足拒绝。这不包括运行时研究折扣及其他 Mod 的配方修改。

## 项目结构

```text
mod/Scripts/
  main.lua                        UE4SS 入口／原生桥接状态
  config.lua                      数量／递归限制与候选配方选择
  BetterWorkbench/
    RecipeBook.lua                原配方快照与产物索引
    RecipeNormalizer.lua          已观察到的扁平材料字段转换工具
    VirtualInventory.lua          真实库存与虚拟余量
    RecipeResolver.lua            递归求解
    BatchSchedule.lua             整批与逐件实际投入安排
    NativeSnapshotPlan.lua        原生数据的只读规划和自动日志
    JobPlan.lua                   任务成本视图与保存数据一致性校验
    CraftService.lua              预览／服务端重新求解接口
    DisassemblyPlan.lua           整批分解与原始材料返还计划
    DisassemblyCapacity.lua       所有返还材料的共同背包容量检查
    DisassemblyRuntime.lua        分解库存范围、原生返还和成品扣除
    DisassemblyUI.lua             详情数量入口、模式切换与手柄导航
    DisassemblyProbe.lua          手动一次性只读原生接口探测
    MaterialScroll.lua            原生材料行滚动与动态可视高度
    CancellationPlan.lua          离线材料守恒参考，不接入游戏退款
    PalworldAdapter.lua            待验证的游戏接入点
    Diagnostics.lua                只读反射检查与调用日志
    MaterialAudit.lua              配方／UI 材料读取、制作前后槽位比较
tests/fixtures/recipes.lua               合成测试数据，不是帕鲁真实配方
tests/run.lua                      Lua 测试
tests/disassembly_runtime.lua      分解运行时与 UI 模拟测试
tests/run.py                 Lua 5.4 测试运行器
tools/check_cooked_recipes.py       本机静态配方校验
tools/deploy.ps1                   备份、部署与哈希校验
docs/INTEGRATION.md                接入契约、实机验收与本机证据
```

## 离线测试

需要 Python 和 `lupa`；测试直接执行项目中的 Lua 5.4 代码，不用 Python 重写算法。

```powershell
python -m pip install -r ../../requirements-dev.txt
python tests/run.py
```

如果有独立 Lua 5.4，也可以从项目根目录运行：

```powershell
lua -e "PROJECT_ROOT='.'; dofile('tests/run.lua')"
```

示例：制作 1 批 `Gear`，原配方需要 `Ingot ×3 + Polymer ×2`。库存已有 `Ingot ×1 + Ore ×4 + Polymer ×2`，且每个 `Ingot` 消耗 2 个 `Ore`，结果为 `Ingot ×1 + Ore ×4 + Polymer ×2`。原配方保持不变。

## 边界与决策

`batches` 指配方执行次数，最终产量为 `batches × OutputAmount`。材料清单是**整个批量计划的总成本**，不能直接除以批数作为单份 UI 配方：中间材料会向上取整。

核心只做确定顺序的库存优先展开，不进行全局最优搜索。只读电池验证器在没有明确配置时，先尝试完整的煤炭计划，再尝试使用已有木炭的完整计划；不会跨炉子制作木炭。实际适配器仍须检查科技及服务器权限；只读计划标注 `EligibilityVerified=false`，不能用它授权制作。

本阶段采用保守的余量规则：虚拟中间产物余量仅在同一个计划内复用，不发到玩家库存，也不跨任务留存。合计工作量包含所有展开步骤；游戏适配仍需验证它如何进入原生生产任务，不能以根配方原工作量替代它。

## 游戏接入状态

已找到本机游戏目录 `G:\SteamLibrary\steamapps\common\Palworld`，近期日志显示 UE4SS `v3.0.1 Beta #0` / SHA `2281fa31`；Steam manifest 的 build ID 为 `25246127`。这些记录不等于已完成当前运行版本的兼容验证。

2026-10-06 已按用户要求部署到 `G:\SteamLibrary\steamapps\common\Palworld\Mods\NativeMods\UE4SS\Mods\BetterWorkbench`，并在该目录的 `mods.txt` 添加 `BetterWorkbench : 1`。更新后的 11 个部署文件已与源码逐个核对哈希。原文件备份在项目 `.tools/deployment-backups`。11:52:56 日志确认首版入口加载成功；12:17 与 12:19 日志确认制作、生产完成与领取流程。新增材料审计仍需重启游戏加载。当前不改变制作行为。

调试时重启游戏，进入存档，打开制作台，选中配方并更改制作数量。日志中查找 `[BetterWorkbench:Probe]`：`PROPERTY`／`FUNCTION` 记录反射定义，`PARENT` 记录实际父类，`HOOK` 代表注册成功，`CALL`／`POST` 才证明实际调用经过它，分别记录 native 函数前后状态（Blueprint hook 在执行后记录）。一般每个 hook 每阶段最多记录 12 次，频繁 getter 最多三次，总计最多 150 次；类查找最多持续 4 分钟。12:13 日志已确认打开工作台、按钮材料初始化、服务器配方变更和取消任务的实际调用。可在 `Scripts/config.lua` 设置 `Diagnostics.Enabled = false` 后重启关闭诊断。

**材料审计已隔离，不再接入游戏回调。** 以下是离线实验模块的行为，当前游戏不会输出这些记录：`AUDIT BEGIN/END` 对本次启动中观察到创建的任务比较操作前后的已加载世界槽位，`AUDIT SLOT` 显示变化及所属对象，`AUDIT RECIPE/UI` 显示原始配方与界面材料。这不是已授权的制作库存范围，也不用于扣料或可制作判定。快照不完整、槽位销毁／新建／复用会显式标为不确定，不把缺失槽位直接当作扣料；其他玩家和 Mod 同时改变库存也可能影响观察。最多审计 24 次操作，每个任务只采样前两次生产完成。设置 `Diagnostics.MaterialAudit = false` 可仅关闭库存审计。

2026-10-06 12:24:38 出现 UE4SS 访问违规崩溃（启动后 16 秒），早于 12:25 开启自动重载；不能将这次崩溃归因于自动重载。当前已将 `mods.txt` 中 BetterWorkbench 改为 `0`，源码与部署配置的 `Enabled`、`Diagnostics.Enabled`、`MaterialAudit` 均设为 `false`，并恢复 `EnableAutoReloadingLuaMods = 0`。用户确认停用后可正常启动，因此最近新增诊断是主要嫌疑；尚未确定具体崩溃位置。随后已撤回诊断中的 MaterialAudit 接入、新增四个反射类与 CollectLocalPlayerControllableItemInfos 钩子，恢复达到日志上限后立即停止参数读取，保留原生 post 参数顺序修正。当前重新部署并启用基本制作日志（`BetterWorkbench : 1`、`Enabled = true`、`Diagnostics.Enabled = true`），材料审计仍为 `false`，自动重载仍为 `0`。这次恢复版本需下次重启验证，不能视为已确认修复。25 项离线测试通过，包含达到日志上限后不访问参数的检查，但不验证原生内存安全。日志与崩溃报告保存在 `.tools/crash-evidence-20261006-122652`，旧配置和部署文件保留在 `.tools/deployment-backups`。

下一步见 [游戏接入说明](docs/INTEGRATION.md)：识别原生材料视图、批量数量变化、可制作判定和服务器生产请求，再完成 UI 与扣料的同一计划接入。

用户随后再次要求开启自动重载，已将本机 UE4SS 的 `EnableAutoReloadingLuaMods` 改为 `1`，修改前配置保存在 `.tools/deployment-backups`。当前进程仍需重启一次才会创建文件监听；实际重载尚未验证。材料审计保持隔离。

## 原生桥接候选

原生只读桥接已编译并完成部署前检查，见 [docs/NATIVE.md](docs/NATIVE.md)。它在原版需求函数返回后立即复制材料名称和数量，保留原版研究计算。参考 PalCombo 后确认其依赖固定到运行时的 UE4SS `2281fa31`：此前读取到的是外层仓库提交号。177 个相关头文件与匹配版本一致，桥接的 27 个 UE4SS 导入接口均存在；启动时还会核对游戏函数和原生材料结构。不修改配方、库存或制作任务，穿透仍关闭，实机验证待重启后完成。

## 当前工作台限制

用户明确要求禁止跨工作台生产穿透。核心要求服务端快照提供 `Context.StationRecipes`，值为当前工作台已验证可制作的精确配方 ID 集合（`{ RecipeId = true }`），不能合并基地其他设施的配方。根配方及每个中间步骤都必须在集合中，另须通过科技与权限检查；集合未知时返回 `station_scope_unverified`，不属于当前工作台时返回 `cross_station_recipe`。已有中间材料可以使用，缺口不会穿透到其他工作台原料。碳纤维缺木炭时仍缺木炭，不能用木材替代。此前跨设施离线示例仅为历史计算实验，不再是目标行为。26 项离线测试及 1,414 条本机配方校验通过；游戏材料视图与扣料接入尚未实现。

2026-10-06 最新接入进展：已实机读取制作台的 552 条配方（不含炉子木炭配方）、12 条原生 UI 材料需求，以及 6 组本地背包／基地数量样本。两种库存范围仍分别保留，原版按钮使用的实际库存收集策略尚未确认。研究减耗新增按步骤、按批量的 `Context.materialsForBatches` 接口，根配方与同工作台中间配方分别取有效总成本，提交时重新求解；游戏快照必须设置 `RequireEffectiveCosts = true`，成本未确认则拒绝。38 项离线测试及 1414 条配方校验通过。原生库存收集器钩子与世界槽位扫描继续关闭，服务器成本提供器、UI 展示变更和扣料仍未实现。

最新方向：遵照用户要求，优先复用游戏已有的材料需求、研究减耗、库存收集、扣料及取消返还方法；Mod 负责同工作台的缺口展开与协调，不另写游戏经济规则。`CraftService.cancel` 已改为直接委托原生后端接口，自定义退款仅留作离线守恒参考。45 项测试通过。当前只读诊断正常，穿透仍未启用；原生方法能否接受展开后的投入及正确退款尚需验证。
