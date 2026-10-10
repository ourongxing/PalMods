# 更好的快速收纳 / Better Bulk Storage

`0.1.0-experimental`。沿用官方 **Easy Bulk Storage** 的背包入口、按键、确认窗口、排除列表和服务器转移请求，允许新物品进入基地箱子的空槽。

工坊四语介绍位于 `workshop/README.*.md`，通过 `tools/package_workshop.py` 生成列表。

## 使用与限制

在基地内打开背包，照常使用官方批量快速收纳，目标为当前基地。
基地外选择所属公会中建筑数量最多的基地；数量相同时，选择离玩家最近的基地。
数量直接读取基地模型的 `GetBuildingNum()`，不枚举建筑 Actor；没有可用公会基地时不收纳。

灰显只在进入收纳模式后开始。每帧最多推进 32 个状态机步骤，预算 1.5ms；预算在步骤边界检查，不能中断单次游戏调用。
逐个检查普通背包物品并更新灰显，同一物品类型复用本次操作的判定，每个槽位只加入候选一次。
箱子的分类、过滤、访问权限、空槽和未满同类堆叠参与判断；帕鲁蛋可进入允许该分类的空槽。

打开背包和普通整理不会启动扫描。整理、退出收纳模式、关闭背包或切换基地取消任务；再次进入收纳模式才重新扫描。
原版排除列表的增删直接更新已检查物品，不重新扫描箱子；任务完成后不轮询。
确认时处理已经加入列表的物品，未扫描的物品留待下一轮；原版确认窗口和取消行为继续生效。

灰显表示检查时至少存在接收位置，不保证整组物品能全部放下，也不为不同物品预留共享空槽。
结果仅缓存到本次收纳操作结束，箱子内容变化后需重新进入收纳模式更新提示。
基地外不要求客户端加载远处箱子，因此不预测远处箱子的分类或剩余容量。
实际数量始终由游戏服务器校验，放不下的留在背包。

转移时先在所有目标箱子中合并未满的同类堆叠，再将剩余物品放入空槽；每一轮内沿用原版箱子顺序。
仅客户端安装不能改变远程服务器的转移规则。联机需要服务器加载 DLL、客户端加载完整 Mod，联机尚未验收。

支持的本机游戏 EXE SHA-256：
`e590b5e7bfaa3fea40fab1a02cc72c8fc5fd6f8631ef2308e95ac56c25195837`。
UE4SS 使用仓库 SDK 对应的 `2281fa31`；不支持的游戏版本或被修改的原生函数不会启用修改。

## 构建与安装

需要仓库的 Python 依赖、CMake 和 Visual Studio 2022 的 `14.44.35207` 工具链。

```powershell
python mods/BetterBulkStorage/tests/run.py
python mods/BetterBulkStorage/tools/build.py
```

产物：`dist/BetterBulkStorage/BetterBulkStorage-0.1.0-experimental.zip`。
完全退出游戏后，将 ZIP 内的 `BetterBulkStorage` 文件夹放到 `<Palworld>/Mods/NativeMods/UE4SS/Mods/`。
Lua 和 DLL 必须一起更新；旧桥接接口会被 Lua 拒绝，以免混用版本。

```text
BetterBulkStorage/
  enabled.txt
  README.md
  dlls/main.dll
  Scripts/main.lua
  Scripts/Preview.lua
```

从 `EnhancedBulkStorage` 升级时先移除旧 Mod，避免同时加载。
卸载时退出游戏并移除 Mod 文件夹；不覆盖游戏 EXE 或原版资源。
不建议同时启用其他修改批量快速收纳候选或原生转移函数的 Mod。

## 验证

2026-10-10：用户确认基地内、野外收纳及当前分帧灰显使用效果良好；容量不足时的灰显限制保留。
自动回归核对 36 个反射接口签名、调用参数和原生字段偏移，并检查受支持游戏的二进制布局。
Lua 测试覆盖入口触发、分帧限额、取消、排除列表、重复物品、锁定、分类、帕鲁蛋、实体 ID 查询和基地切换。
200 箱×1000 槽及 200 条密码记录的模拟检查任务不会在单帧无限推进。
C++ 测试直接运行 DLL 使用的转移实现，覆盖跨箱堆叠优先、溢出、原生拒绝、动态 ID 和失效对象。
保存重载、联机、关闭确认窗口等边界场景仍需游戏内逐项验证。

## 实现

原生服务器调用方 `0x2dbd5b0` 在 `0x2dbd9d6` 调用收纳辅助函数 `0x2da9a60`。
DLL 校验 PE 元数据、完整辅助函数、调用位置及容量/事务/权限/过滤函数的字节后，在辅助函数入口安装 14 字节绝对跳转。
新实现分两轮遍历目标箱子，先合并再放空槽；容量查询仍调用 `0x2fad5a0`，转移仍调用原事务 `0x2fbc1f0`。
保留目标和来源槽位 ID、事务上下文、RPC 参数和存档格式；卸载时恢复原入口。
构建审核记录保存在 `.build/BetterBulkStorage/native/analysis.json`。

DLL 的 Blueprint 执行前后回调限定背包调用范围，只在该范围内补充本地玩家为空的基地查询。
候选基地来自公会 `BaseCampIds`，解析后复核所属公会，再按建筑数量和距离选址。
不修改玩家实际所在地、全局基地判定或服务器权限。

原生 `ToggleQuickStackPanel` 执行前启用预览状态，抑制当前控件同步的 `UpdateQuickStackableInventorySlot(Editing=true)` 和逐槽灰显。
UE4SS 的蓝图 Lua Hook 只有执行后回调，面板可见后才启动 `Preview.lua`；`Editing=false` 仍沿用原版恢复行为。
状态机直接在 UE4SS 注册的游戏线程回调中执行，避免未注册 Lua 协程访问 UObject。
容器索引存储实体 ID，使用 `FindConcreteModel` 查询；数组输出参数直接写入传入表的数字索引，对象输出参数保留字段名。
预览复用原生只读权限/过滤判定，惰性读取箱子槽位，直接更新 `CurrentStackableSlotIds` 和颜色；不增加转移 RPC。
排除物品和动态分类只影响本次候选，不修改 `HasDynamicItemClass` 的全局返回值。
Blueprint 尚未加载时通过对象创建通知安装入口 Hook，不持续搜索场景；取消后的过期帧回调不再访问游戏对象。
