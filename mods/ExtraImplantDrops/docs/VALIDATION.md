# 植入体掉落验证记录

## 2026-10-20：Windows 专用服务器本地适配

### 范围与实现

- 目标：将当前单机掉落逻辑用于本机 Windows 专用服务器，覆盖原生普通死亡和肢解掉落路径，不增加额外客户端发奖请求。
- 保持 28 种规则、每种独立 50% 默认概率、原生数量构造器及世界／伙伴／被动加成计算。
- 旧 DLL 的程序指纹和地址限定客户端，且未在服务器安装。本次生成独立服务器函数保护信息和 DLL。
- 按肢解调用方、普通死亡调用方、builder 的 processor 调用、processor 和 getter 的直接调用逐一定位服务端函数。
- 生成阶段验证服务端完整程序 SHA-256，并对两条掉落链、被动数组偏移、掉落元素 0x28 字节布局、概率和数量参数进行相同 ABI 断言。
- 运行时仍检查 PE 指纹及 12 段完整函数字节；不匹配时拒绝挂接。
- 客户端源逻辑和已安装客户端 DLL 未改动；未发布工坊。

### 环境与安装

- 服务器：`G:/PalworldTestServer`，`PalServer-Win64-Shipping-Cmd.exe`。
- 程序 SHA-256：`6f929673e7ac637d591d6f3454dbd396be7911093311cb8b24af3a152b217f49`。
- UE4SS：`2281fa31`，服务端运行库 24 个导入全部核对通过。
- 世界：用户迁入的“遵守规矩”服务器副本 `B6FC599AEB02496A9EF1E420FD1C41DF`。
- 游戏未运行时正常关闭服务器，备份当前 Saved 后安装，再完整重启。
- 配置沿用客户端，`DropChance=0.5`、`Debug=0`，没有为测试提高概率或改变数量。
- 备份：`.build/implant-server-20261020/Saved-before-install/`；安装备份见 `.build/install-backups/ExtraImplantDrops-20261020-133942-46221f3ea0434db782137dba7d7ae4db/`。
- 本地安装目录：`G:/PalworldTestServer/Mods/NativeMods/UE4SS/Mods/ExtraImplantDrops/`；使用本地开发安装方式，没有启用旧客户端工坊包的服务器规则。

### 已完成验证

- 客户端、服务端原生编译均通过，分别核对全部 24 个 UE4SS 导入。
- 两端实际原生数量构造器在隔离内存中验证：10000 次调用、分数世界倍率、叠加加成、50% 成功／失败及全部 32768 种随机结果。没有向运行中的游戏注入该测试。
- C++ 掉落规则测试 `extra_implant_drops_drop_plan` 通过。
- 启动日志明确报告 `installed native death-drop hooks; extra chance=0.5 base_count=1; game rates; rules=28`。
- 安装 DLL 与服务器构建审核哈希一致，连接端口正常监听。证据保存在 `.build/implant-server-20261020/`，构建分析与导入审核在 `.build/ExtraImplantDrops-server/`。

### 待实际验证

最终服务端版本安装后，用户反馈“可以了”，确认当前服务器的植入体掉落可用。
此项为用户实机确认，不是代理实际操作；用户未说明分别测试了普通击杀还是肢解，不能补写为两条路径均已逐项覆盖。

仍待逐项确认：普通击杀与肢解的各自覆盖、原版材料保持、连续操作不重复发放、数量倍率、第二位玩家和保存重载。
50% 概率下单次未掉落不能单独判定失败。

## 2026-10-20：工坊 1.1.0 发布

- 沿用 PublishedId `3820049962`，包内分别提供客户端 `dlls/main.dll` 和服务端 `Server/dlls/main.dll`。
- 服务端 `Lua` 安装规则使用 `./Server/` 复制目录内容，部署到同一 Mod 根目录，避免多套 Server 子目录。
- 两端原生编译与全部 24 个 UE4SS 导入检查通过；掉落规则测试和 15 项工坊打包测试通过。
- 四语说明已从 Steam 读回核对，公开状态、封面、标签及 UE4SSExperimentalPW 依赖保持不变。
- 通过游戏 AppID 重新下载，13 个包内文件全部匹配发布清单，独立服务端 DLL 与安装规则均存在。
- 停服并备份 Saved、旧本地安装、工坊包与配置后，本机服务器切换到正式包并完整重启。
- 官方部署后的 DLL 哈希与正式服务端产物一致；日志再次确认挂接成功，监听 `127.0.0.1:8211`。
- 用户实机确认来自此前同一实现的测试版本；本次发布版本没有另行补记新的游戏操作验收。
- 发布包：`dist/workshop-extraimplantdrops-server-1.1.0-20261020/ExtraImplantDrops/`。
- 上传、页面读回、下载校验和本机迁移证据：`.build/workshop-extraimplantdrops-server-1.1.0-20261020/`。
