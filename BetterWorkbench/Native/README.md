# better workbench（更好的工作台）Native 0.6.0 dynamic inputs

当前统一安装在 `Mods/BetterWorkbench`：`dlls/main.dll` 与 `Scripts/main.lua` 共用一条 `BetterWorkbench : 1`。任务定义保存在 `BetterWorkbench/Jobs`；部署脚本迁移旧 `SmartRecipe/Jobs` 和 `SmartRecipeNative/Jobs`，旧目录完整移出 Mods 保存至部署备份。迁移及原生更新必须正常退出游戏后执行。

0.6.2 将单位制作的完整移除数组交给原生事务 0x2fbc2f0，限定调用点 0x30135d1；其他调用保持原样。原生完成函数 0x3012d70 在 0x3012f97 使用固定五槽上限，本版本替换它生成的移除清单。元素原生布局为 24 字节：容器 GUID16、物理槽索引4、数量4。投入槽 GUID／索引／物品／数量在进入原生完成函数前验证；数量完全来自已保存的原生研究成本单位计划。线程局部上下文只存在于同步完成调用期间，产品记录、权限与上下文参数传回原方法。DEBIT 日志核对各槽实际数量变化，不能以 accepted=true 作为已正确扣料的证明。实机扣料修复仍待验证。

0.6.1 修复输入槽 0x300d010 和索引 0x300e280 的构造返回约定。原生方法先清空输出头；调用方可能传入未初始化栈内存。动态替换必须先清零，异常时也返回有效的空数组，不得释放未初始化字段。0.6.0 触发的 MallocBinned2 canary 断言对应退款准备函数 0x3023e70 清理错误数组。新增二进制保护覆盖原生输出初始化位置。

本候选版已启用经实机探测匹配的 PalItemContainer 原生扩容方法。实际 vtable 容量函数为 0xdbe790，扩容实现为 0x2fa6c00；通过包装函数 0x2e8d210 扩容，只增加容量并核对原槽指针保留。原生成品槽固定为索引 5，额外输入映射至 6..64。材料 ID 枚举由不可变 Jobs 定义提供；原生转移与材料槽查找两个直接按物理位置索引的调用点在位置 5 插入 None，验证与退款得到紧凑数组，对应紧凑输入槽数组。全部调用位置由游戏 SHA 和代码字节保护；非匹配容器保留五槽策略。

64 种投入的规划不再跳过库存中的中间件。SRJ4 定义保持旧格式兼容并接受最多 64 种材料；保存进度仍来自原生任务字段。需要实机验证：混合碳纤维库存制作电脑、部分生产后取消、保存退出后恢复，以及成品领取。离线测试只验证规划、索引和定义往返，不能证明游戏存档是否保留扩容槽。没有恢复 0.4.2 缓存或 Lua 后台轮询。

以下 0.5.x 段落是历史记录。

扩容实验第一阶段：Computer 查询触发一次同步 C++ 容器探测，读取实际容器类、槽数、五输入槽映射、原生容量／扩容虚函数 RVA，以及模块和容器的反射字段偏移。探测不扩容、不保留 UObject、不接入 Lua 轮询。新调用位置有本机 PE 字节保护。原生扩容包装函数已定位为 RVA 0x2e8d210：调用 vtable+0x2b0 读取当前容量，扩容请求较大时调用 vtable+0x2d8 的实际实现。必须核对真实工作台的虚函数实现、输入／输出槽布局和存档容量恢复后才能启用容量写入。当前仍按最多五种实际投入工作。

0.5.1 的五槽规划保留原始库存优先结果；仅当混合现有中间件与原料导致超过五种投入时，最多尝试 64 个同工作台中间件替换方案（单项／双项）。被替换的库存保持原样，原料仍由原生库存查询验证。没有修改游戏容器容量，无法在五槽内执行的方案仍退回原版。预览与实际制作共用此策略，缺料预览不授权制作。Computer 成本／库存／失败原因使用独立、有界日志额度。

0.5.0 移除界面预览、制作入口和 Jobs 恢复中的测试配方白名单，支持当前工作台原生 GetRecipes 提供的全部根配方。依赖图只纳入同工作台、已解锁的配方；原生单批需求提供研究减免后的成本，原生库存查询、转移、扣料、退款和任务保存方法继续负责实际操作。

运行时回退到 0.4.1 的调用顺序：先调用原版材料／数量方法，再覆写已初始化的材料数组。0.4.2 库存、需求、最大数量和名称缓存全部移除；Lua 诊断与后台轮询默认关闭。没有跨回调保存原生对象。每次查询只对根配方的生产依赖读取成本和库存。

根配方、配方 ID 与产品 ID 不要求相同；中间配方支持每批多产出及批内剩余共享。任意合法根配方均可保存 Jobs 定义，旧碳纤维／电池定义保持兼容。依赖循环、跨工作台、未解锁配方、超过 256 批、超过 5 种实际投入时保留原版行为。原生五材料槽限制仍在，因此“全部根配方参与规划”不代表任意展开都能执行。

0.5.0 新增原生测试覆盖非测试白名单的武器根配方、多层生产链、不同配方／产品 ID、多产出、工作台与解锁排除、循环和新根配方 Jobs 往返。实机启动及新配方制作待部署验证。启动日志应出现 `RECIPE_SCOPE all native current-workbench recipes`。

## 历史实现记录

以下记录保留早期版本的 ABI 与调用位置证据；其中焦点配方及只读状态不代表 0.5.0 的当前运行范围。

0.4.1 将穿透计划写入原生 UI 的材料数组，保留游戏原版图标、名称、拥有／需求数量和不足提示。配方卡片使用单批需求；数量详情在原生倍率处理完成后替换为整批精确投入，避免混合库存被重复相乘。材料不足时预览也显示需要的原料，实际制作仍用严格服务器校验。53 个运行库导入核对及原生计划测试通过，界面刷新效果尚待实机确认。

0.4 已接入焦点配方的实际制作入口，默认启用。支持 CarbonFiber、CarbonFiber2、Bio_Battery；最多 256 批、5 种实际投入。启动成功以日志 `ACTIVE_CRAFTING enabled` 为准；编译及离线测试通过不等于实机验收完成。

服务器重新读取当前工作台、原生科技权限、原生研究减耗后的成本，以及原生收集函数返回的玩家／基地容器。先用已有中间材料，再展开缺口；炉子的木炭配方不参与。用同一份原生输入容器进行最终库存校验，沿用原生转移、逐件扣料、产出、领取和取消退料。

每个需要穿透的任务获得一个独立虚拟配方 ID；全局 DataTable 不修改。虚拟行由 UScriptStruct 深复制，原生拥有的数组不会用浅复制共享。材料槽固定为整个任务的实际投入集合，单位成本由不可变逐件计划提供。原生材料 map 通过游戏自己的清空、哈希及插入方法构造，不套用 SDK 中不匹配的 TMap 元素对齐。

原生存档保存任务 ID、RequestedProductNum 和 RemainProductNum；单位索引来自原生已完成数量。`BetterWorkbench/Jobs/*.bwj` 只保存不可变定义，先持久化再建立任务，具有大小／结构／校验和／游戏版本检查，绑定工作台 GUID。迁移后的旧 `SRJ_` 任务继续读取 `.srj` 文件。不要删除仍有未完成任务的 Jobs 文件。该路径不使用另一个可变完成计数，因此旧原生存档可以恢复对应的旧进度。

当前限制：制作工时仍沿用根配方原生工时，尚未额外计入展开中间件的工时。多人客户端分发这些虚拟任务定义尚未接入，本候选版用于本机测试。权限、布局或版本不匹配时不启用写入；缺少已存在任务的定义时阻止完成。

验证：57 项 Lua 测试（含 200 个守恒场景），2 项原生测试（副本隔离；混合单位／同工作台／科技过滤／方案回退／余量／不可变定义恢复及损坏拒绝），52 个 UE4SS 导入匹配当前运行库。启动、实际转移、逐件扣料、部分取消及重载存档仍待实机确认。Lua 自动重载不能更新 C++ DLL，需要重启游戏。

## 历史只读桥接记录

# Native read-only bridge

## 0.3 候选版（只读，尚待实机确认）

新增同步 worker 作用域：读取当前工作台 GetRecipes（反射验证返回数组），以 worker 的模型作为原生成本函数的 world/owner，再对同一组原生容器查询焦点配方的额外材料 ID。原请求的数组和输出保持原版。新增名称数组由游戏 FMemory 分配并交给原生计数函数消费，桥接复制新结果后用 FMemory 释放；不让游戏释放 vector 或 CRT 内存。

反编译已确认 0x2fa0020 遍历传入容器的非空槽，仅为找到的匹配 ID 建立计数条目。因此，在一次完整查询中未返回的已请求 ID 可记为 0；缺失、部分或失败的诊断数据不适用。非请求 ID 会拒绝。

最多保留 8 份拥有完整副本的快照、最多捕获 24 次焦点请求。BetterWorkbenchNativeTakeSnapshot 返回普通 Lua 数据，在脚本启动／重载时重新注册，原生不保存 Lua 状态或游戏对象。Lua 自动记录只读计划，科技及权限未确认时 EligibilityVerified=false。

新增函数入口有本机二进制检查，材料布局要通过反射检查。0.3 已编译、部署，46 个导入接口匹配当前运行库，副本隔离测试通过。14:42:49 启动日志确认快照 API 和三个读取通道安装成功；具体制作快照待实测。0.3 不修改任务、消耗或存档，尚不是成品制作 Mod。

Read-only detour of the original effective material-demand function. Research
modifiers and rounding remain in the game. The bridge copies the returned
12-byte entries immediately into owned strings and integers. No pointers or
borrowed arrays escape the callback. No recipe, inventory, or job is modified.

Runtime UE4SS reports commit `2281fa31`. PalCombo's dependency setup pins the
same commit. The previously reported `ce04b38` was the enclosing PalCombo Git
repository's commit, embedded as build metadata; it did not establish an SDK
source mismatch. All 177 available UE4SS/first-party `.hpp` files compared equal
against the official `2281fa31` archive, ignoring line endings. The historical
Unreal submodule itself remains unavailable from its published repository URL.
The bridge imports its FName constructors, string conversion, reflection methods,
and mod base from the installed UE4SS DLL. Its 27 UE4SS imports were checked
against that DLL's exports, without loading the DLL into an analysis process.
This supports a read-only trial; it is not a claim of complete SDK equivalence.

`tools/build_native_candidate.py` compiles locally against cached SDK artifacts
without modifying that SDK or the game. Pass `--enable-readonly` to enable the
bridge after the pinned-header audit. It generates binary guards from the
local executable and checks the known direct call target. This is a compilation
check, not runtime validation. `tools/audit_native_imports.py` records runtime
and bridge hashes. `tools/deploy_native.ps1` requires those hashes to match,
backs up the prior files and mods.txt, and installs `BetterWorkbenchNative/dlls/main.dll`.
C++ exception handling does not catch access violations.

Activation also requires native struct reflection to confirm size 12, name
offset 0/size 8, and quantity offset 8/size 4. Once activated, logging is capped
at 12 samples for the known server-worker call site and another 12 for other
call sites across CarbonFiber, CarbonFiber2, and Bio_Battery. A C++ bridge
requires a game restart; Lua auto reload cannot load a changed DLL.

Successful initialization logs `[BetterWorkbenchNative] read-only demand hook installed`.
`NATIVE_DEMAND source=server-worker` identifies the verified direct worker call.
`source=other` only means another call site; it does not establish UI ownership.
Mismatch or unavailable native structures leave the hook disabled. Game behavior
remains unchanged even when the read-only hook is installed.

Actual recipe expansion still requires a per-job recipe view matching native
input-slot identities and order. Replacing only the demand array is insufficient.
Native input handling has five slots; expanded plans beyond that limit must be
rejected until a supported native representation is established. Cancellation
should use actual native input contents and the original cancellation route.

## Observed game validation (2026-10-06)

The deployed bridge captured both direct server-worker calls and copied material
names and quantities successfully. At 13:27:02, Bio_Battery requested one batch:
ElectricOrgan=1, IronIngot=1, CarbonFiber=1; player inventory decreased 16→15,
78→77, and 56→55 respectively. Pickup increased Bio_Battery 59→60.
At 13:27:10, CarbonFiber requested one batch: Coal=2, FireOrgan=1; player inventory
decreased 54→52 and 27→26. Pickup increased CarbonFiber 55→56.
The copied costs matched the native UI samples and observed debit quantities.
These two requests validate this local game's read-only bridge path; they do
not validate expanded inputs, alternative research modifiers, or dedicated servers.
Evidence is preserved locally in `.tools/native-validation-20261006/observed.log`.

## Version 0.2 server inventory scope

Adds a read-only detour of the original stock counting function `0x2fa0020`,
restricted to the verified crafting-worker call site `0x30061ec`. Material names
are copied before the original call, because that function consumes and frees
its by-value name array. The returned stock quantities are copied immediately
after the call. Container pointers and arrays are not retained or scanned by
the Mod. `SCOPE_STOCK` is the original server workflow's returned stock, without
adding separate player/base diagnostic counts. Missing result rows are not
silently invented as zero.

The same callback copies the worker's post-multiplication total demand from its
verified stack-local array (`caller RSP+0x58`, return-address slot +0x60).
This requires the exact caller, game build, demand/multiplication instruction
window, and inventory-call instruction window to match before installation.
`BATCH_DEMAND` and `SCOPE_STOCK` therefore describe one synchronous request.
Both outputs are copied to owned strings and integers; no borrowed data escapes.
Logging is capped at twelve server scope calls. Version 0.2 was observed in the
game at 13:40:33: CarbonFiber x3 demand Coal=6/FireOrgan=3; original server scope
returned Coal=3151/FireOrgan=56. Player coal decreased 52→46 and fire organ 26→23.
Another request at 13:40:46 consumed Bio_Battery, CarbonFiber, MachineParts2 and
Plastic; this was not a Bio_Battery production request. Plastic x101 at 13:42:23
also yielded a correctly scaled original batch-demand snapshot. Expansion and
inventory writes remain disabled. Evidence is in
`.tools/native-validation-20261006/server-scope-observed.log`.

## Recipe-copy preparation (not deployed)

`src/recipe_view.hpp` prepares five slot identities and applies them only to a
caller-supplied native recipe return copy. Native raw-material builders at
0x2fad420 and 0x300ced0 both establish IDs at +0x24/+0x30/+0x3c/+0x48/+0x54
and counts at +0x2c/+0x38/+0x44/+0x50/+0x5c. Presence markers identify slots;
they are not cost quantities. The job's cost arrays/maps remain separate.
The helper rejects incompatible layouts, short buffers, duplicate IDs, empty
IDs, non-prefix slots and invalid markers before writing anything. It leaves
every byte outside +0x24…+0x5f unchanged, including product/work metadata and the
owning array at +0x70. No whole native struct or owning pointer is copied.

The new candidate also validates the reflected GetCurrentRecipe return type,
row size, and five material property offsets/types. All 33 imports are present
in the installed UE4SS. Recipe-view isolation tests passed in Release with
checks active. This candidate is not deployed; the running game retains 0.2.
No GetCurrentRecipe detour or recipe-view write is activated yet.
