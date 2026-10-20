# 肢解动作分支记录

依据本机 `Pal-Windows.pak` 中的
`/Game/Pal/Blueprint/Action/Palmi/BP_ActionCutPalMeat_Player`。
输入资产完整校验值保存在 `tools/build.py`，详细构建校验输出到
`dist/QuickButcher/build-audit.json`。研究导出保存在 `.build/QuickButcher/research/`。

原版 `OnBeginAction` 入口在 Ubergraph 的内存字节码偏移 1489。
检查目标成功后，压入三个续接地址：2501（服务端目标动作）、2481（玩家操作限制）、1836（动画）。
随后设置 `TargetCharacter`、目标移动倍率、表情和碰撞。
执行流栈按后进先出运行，因此目标设置之后先进入动画分支。

动画分支读取动作 75 的蒙太奇，调用 `CreateProxyObjectForPlayMontage`，
绑定完成／打断／通知回调。原版完成回调最终进入 1406：
设置 `bIsEndAction=true`、`IsDeletePal=true`，然后弹出执行流栈。

补丁只把第三个续接地址从 1836 改为 1406：

| 位置 | 原版 | 修改后 |
| --- | --- | --- |
| Ubergraph 磁盘字节码偏移 2273 | `EX_PushExecutionFlow(1836)` | `EX_PushExecutionFlow(1406)` |
| `.uexp` 文件偏移 6579～6582 | `2C 07 00 00` | `7E 05 00 00` |

不会运行蒙太奇播放或动画通知分支。之后仍执行操作限制与服务端目标动作。
原生动作生命周期根据结束标记调用 `OnEndAction`（2958），其中保留：

- 恢复玩家的跳跃、闪避、移动与转向设置，停止对应动作蒙太奇。
- 服务端检查 `IsDeletePal`，启动原版目标死亡动作并设置肢解相关标记。
- 原版延迟回调（1 秒）继续发放肢解掉落、增加肢解次数、通知移除随行帕鲁，最后允许销毁动作实例。

`GiftItem_FromOtomoCutMeat`、`PalButcherCount`、`LostOtomoByID_ToClient` 和
所有原生发奖／删除接口的调用字节均未改动。无效目标仍进入原版失败分支。

UAssetAPI 1.1.0 的 CLI 需使用已注册的 `Palworld` mapping 名称读取反射字段。
该版本不能完整解码此 Ubergraph 中两个 `PalAIActionDynamicParameter` 结构体表达式；
分析分段读取其前后字节码，跳转偏移用 `ExpressionSerializer.WriteExpression` 的内存长度校对。
构建不依赖解析器，而以完整源文件哈希及精确的三条压栈指令校验补丁适用性。

这是静态流程证据。单机连续肢解、结算一次性、角色恢复和联机表现仍需游戏内验收。

## Windows 专用服务器资源

2026-10-20 本机 `Pal-WindowsServer.pak` 的同名蓝图具有独立 cooked 文件，不能使用客户端 PAK 替代。
服务端 Ubergraph 的磁盘起点为 4409，内存字节码长度仍为 3770；三个续接地址与完成分支一致。
原始字节码的 35 个差异均对应 NameMap 索引变化，解析后名称相同。
服务端补丁保持自己的 `.uasset` 不变，只修改 `.uexp` 的 6683、6684 两个字节。
完整源文件 SHA-256 另存于构建工具的 `SERVER_HASHES`。

`python mods/QuickButcher/tools/build.py --server --game-root G:/PalworldTestServer`
生成独立的 `dist/QuickButcher/server/` 产物，不覆盖客户端产物。
退出游戏并停止服务器后执行 `mods/QuickButcher/tools/install_server.ps1`，
将独立资源放入现有服务器工坊包副本 `Server/Paks/`，由官方加载器部署。
安装脚本不修改订阅源目录和线上工坊，先备份包、配置和服务器存档。
工坊 `1.1.0` 同时打包 `Paks/` 客户端资源与 `Server/Paks/` 服务端资源，
两条安装规则分别部署到对应运行端。打包工具逐一核对两份构建审核和 PAK 哈希。
