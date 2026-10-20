# 植入体掉落（ExtraImplantDrops）

1.1.0 · ourongxing

帕鲁死亡或肢解产生掉落物时，有概率额外掉落其词条对应的植入体，不影响原有材料。

支持 28 种植入体，每种独立判定，默认概率 50%。基础数量为 1，受游戏掉落加成和世界设置影响。

## 配置

编辑 `config.ini`，修改后重启游戏：

- `DropChance=0.5`：掉落概率，范围 0～1。
- `Debug=0`：调试日志，0 关闭、1 开启。
- `[Implants]`：各植入体独立开关，1 开启、0 关闭；特殊词条单独分组。

## 安装

需要 UE4SS。将安装包中的 `ExtraImplantDrops` 文件夹放入 UE4SS 的 `Mods` 目录，启用后重启游戏。

## 专用服务器

Windows 专用服务器使用独立 DLL，客户端 DLL 不能直接替代。服务端负责生成实际掉落，
概率与词条开关读取服务端 `config.ini`；客户端无需额外协议。

构建：`python mods/ExtraImplantDrops/tools/build.py --server`，产物位于
`dist/ExtraImplantDrops/server/`。退出游戏并停止服务器后执行
`mods/ExtraImplantDrops/tools/deploy.ps1 -Server`，默认安装到 `G:/PalworldTestServer` 的 UE4SS Mods 目录。
已有服务端配置会保留；首次安装优先沿用本机客户端现有配置。
服务器完整重启后加载。工坊 1.1.0 同时包含客户端 DLL 和独立 Windows 服务端 DLL，
官方加载器按运行端分别部署。用户已确认本机服务器掉落可用，具体范围见 [验证记录](docs/VALIDATION.md)。

客户端与服务端构建分别校验对应原生程序的完整 SHA-256、12 段相关函数及调用参数。
程序不匹配时不安装钩子，游戏更新后需要重新核对。
