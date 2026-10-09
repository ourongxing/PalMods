# 批量存储增强 / Enhanced Bulk Storage

`0.1.0-experimental`。2026-10-09：用户安装后确认，本机沿用官方操作的增强收纳可用。

沿用官方 **Easy Bulk Storage** 的背包入口、原有按键、确认窗口、排除列表和基地转移请求。
允许基地箱子尚未持有的物品进入空槽，无需新快捷键或额外收纳界面。

## 使用与限制

在基地内或基地外打开背包，照常使用官方批量存储。基地内仍收纳到当前基地；
基地外收纳到玩家所属公会中距离最近的基地，以玩家和基地中心的三维直线距离选择。
没有可用的公会基地时不执行收纳。排除物品仍通过官方界面管理。
原版的“是否显示确认窗口”设置继续生效，取消操作不会触发额外转移。

第一版在原生候选查询中补充背包物品；候选列表表示尝试存储，不保证全部能放入。
实际数量和结果由官方服务器转移事务决定。当前没有新增蛋孵化、售卖或公会箱规则。
每个箱子内仍先合并同类堆叠再尝试空槽，跨箱子顺序沿用原版。

支持的本机游戏 EXE SHA-256：
`e590b5e7bfaa3fea40fab1a02cc72c8fc5fd6f8631ef2308e95ac56c25195837`。
UE4SS 使用仓库现有 SDK 对应的 `2281fa31`。其他版本自动拒绝启用原生修改。
单机需要本机加载完整 Mod；联机需要服务器加载 DLL、使用增强界面的客户端加载 Lua。
仅客户端安装不能修改远程服务器的原生转移规则；联机尚未验收。

## 构建与安装

```powershell
python mods/EnhancedBulkStorage/tests/run.py
python mods/EnhancedBulkStorage/tools/build.py
```

构建产物：`dist/EnhancedBulkStorage/EnhancedBulkStorage-0.1.0-experimental.zip`。
完全退出游戏后，将 ZIP 内的 `EnhancedBulkStorage` 文件夹放到：
`<Palworld>/Mods/NativeMods/UE4SS/Mods/`。

```text
EnhancedBulkStorage/
  enabled.txt
  dlls/main.dll
  Scripts/main.lua
```

不覆盖游戏 EXE 或原版资源。卸载时退出游戏并移除整个 Mod 文件夹。
不建议同时启用其他修改批量存储候选查询或原生转移函数的 Mod。

## 验证

DLL 编译、Lua 候选查询、最近公会基地选择回归和 UE4SS 导入兼容性检查通过；
2026-10-09：用户确认基地内和新增基地外收纳均在本机可用。
以下边界情况尚无逐项验收记录，联机行为也未验证：

使用可恢复的测试存档，先核对日志包含 `native empty-slot enhancement ready` 和
`official inventory candidate hook registered`，以及新增的 `scoped nearest-base storage ready`，再检查：

1. 基地只有一个空箱，新物品成功存入，背包和箱子数量总和不变。
2. 箱子禁止该分类时，物品留在背包；允许该分类时成功存入。
3. 官方排除列表内的物品保持不动，移除排除后可存。
4. 空间不足、已有堆叠满额时，正确部分存储，剩余数量留在背包。
5. 有确认窗口时取消不移动；关闭确认窗口后原入口仍可操作。
6. 装备、食物栏、关键物品不被补充枚举；普通背包中的不可叠加物品数量正确。
7. 基地外操作存入最近的公会基地；更近的其他公会基地不被选中，无公会基地时不移动。
8. 保存、重载、连续操作后无重复物品或丢失。
9. 多基地之间移动后重新操作，目标随当前位置更新；基地外取消确认不移动物品。

## 实现证据

构建脚本在 `.build/EnhancedBulkStorage/native/analysis.json` 保存二进制审核记录。官方服务器基地存储函数
`0x2dbd5b0` 是 `0x2da9a60` 的唯一直接调用方；后者先合并，再进入空槽循环。
`0x2da9bcd` 的六字节条件跳转在该箱子没有匹配物品时跳过空槽循环。
DLL 将这一处跳转改为 NOP，保留两处原生事务 `0x2fbc1f0`，未更改 RPC 参数或存档数据。
加载前核对 PE 元数据、完整转移函数字节和服务器调用位置，卸载时恢复原字节。

Lua 仅在原版背包组件且 `CurrentInBaseCamp=true` 时补充查询结果，且必须确认本进程 DLL
已成功安装。使用同一 DLL 的 Lua 导出检查状态，不使用可能遗留的就绪文件。
官方的后续排除和槽位选择逻辑仍负责决定提交的物品。

DLL 通过成对的 Blueprint 执行前后回调限定背包收纳调用范围；Lua 仅在这一同步范围内，
为本地玩家原本为空的 `GetInsideBaseCampModel` / `GetInsideBaseCampID` 查询补充最近公会基地。
候选基地来自公会 `BaseCampIds`，逐个通过基地管理器解析并复核所属公会。
原版界面据此启用收纳按钮，后续请求沿用官方目标基地 ID、槽位、确认和服务器事务。
不修改玩家实际所在地、全局基地判定或服务器权限校验；回调不可用时关闭基地外能力。
