# Better Storage / 更好的收纳

基地内沿用原版快速收纳的候选和灰显；野外将主基地 ID 传入原版基地候选接口，使用与基地内相同的筛选和数量规则。保留原版排除列表、确认窗口和服务器转移规则。箱子中没有同类物品时，不会将新物品放入空槽。原版分类、权限及容量检查继续生效。

保留野外选择公会建筑数量最多的主据点（同数量选最近）、普通物品 99,999 堆叠上限，以及同优先级帕鲁搬运优先叠放。

古典大型橱柜与古典书架（`Shelf07_Stone`、`Shelf01_Stone`）通过 PalSchema 蓝图补丁设置为 360 格、仅存放设计图。公会库存创建容量通过 `BP_PalGameSetting_C.GuildChestSlotNum` 设置为 360 格，所有公会箱子仍共享原版公会库存。

家具容量与过滤、以及新公会容量采用 PalSchema 加载时蓝图数据补丁，参考 Schematic Shelf 的方案。旧公会库存由服务器登记新建/重建公会箱子、或箱子实体进入世界时按需迁移：只处理该箱子所属公会，容量不足才调用原版方法补充真实槽位，保留原槽位和物品。迁移目标直接读取同一配置文件中的 `GuildChestSlotNum`，不依赖运行时游戏设置继承蓝图默认值。没有周期全量扫描；初始化未完成时仅为本次箱子事件最多尝试 6 次，每次相隔 1 秒，成功及超时原因写入 UE4SS 日志。

配置文件：`PalSchema/mods/BetterStorage/blueprints/storage.json`（源码为 `schema/blueprints/storage.json`）。两个家具的 `SlotNum` 和公会设置 `GuildChestSlotNum` 可分别调整，重启游戏或服务器后生效。此补丁需要 PalSchema；联机安装在主机或服务器，客户端不能改变服务器库存。

**旧存档无需重开。** 旧书架/橱柜需要重建才能采用新容量和过滤配置；公会箱子新建、重建或随存档加载进入世界时尝试对应公会共享库存扩容。共享库存仍属于公会，不随箱子销毁重建。此前保存的槽位和物品保留；迁移只扩容不缩容，已达到配置容量则不再补槽。扩容仅由主机或服务器执行。

360 格箱子打开时仍由原版 UI 创建槽位控件，数据补丁并不减少此界面开销。用户已确认普通箱子正常，而扩容箱子打开时及保持打开时帧率较低；当前保留 360 格，不修改箱子 UI。原建造入口实测未完成扩容，现增加原生 Actor BeginPlay 入口及配置读取；旧库存迁移、保存重载与联机同步仍需实机验收。

野外直接调用原版 CollectQuickStackTargetItemInfos，传入主基地与本地玩家 ID。基地查询限定于背包蓝图执行范围，类名校验按弱引用缓存。

构建：`python mods/BetterStorage/tools/build.py`。

产物：`dist/BetterStorage/BetterStorage-0.1.0.zip`。

退出游戏后，将 ZIP 中的 `BetterStorage` 和 `PalSchema` 两个文件夹合并到 UE4SS/Mods，保留已有 PalSchema 插件。更新旧版时删除 `BetterStorage/Scripts/BlueprintStorage.lua`、`StorageWatch.lua` 和 `config.lua`；`GuildStorage.lua` 应替换为新版建造事件迁移脚本。先禁用 BetterBulkStorage，两个 mod 不能同时启用。

联机的堆叠上限与搬运修改需要主机或服务器加载 DLL；野外收纳沿用服务器验证，联机尚未验收。

2026-10-10：用户确认本机野外收纳及灰显符合主基地规则。

2026-10-10：用户确认取消周期全量扫描后站立掉帧消失。扩容方案随后简化为 PalSchema 加载时蓝图数据补丁，用户确认扩容箱子仍有界面帧率开销，接受保留当前容量。随后补充新建/重建公会箱子时的旧库存迁移。
