# CustomPresets 验证记录

## 后台菜单搜索优化（2026-10-19）

目标：保留世界及人物预设的创建、选择、保存、删除与缩略图流程，移除正常游玩期间不必要的全局菜单搜索。原代码每 750 ms 对人物创建、世界设置各执行一次 FindAllOf，约每秒 2.67 次。

实现：启动时仅补查一次已有菜单；之后通过两种菜单类的 NotifyOnNewObject 注册精确实例，游戏线程轮询仅处理这些实例。保留可见状态判断、关闭恢复、失效对象清理、原有预览节流及异步队列防重入。

离线验证：`tests/run.py` 通过，涵盖世界和人物预设的持久化、选择、保存、删除、语言、原生桥接失败恢复和缩略图生命周期。新增创建通知接入、连续 100 次空闲轮询全局菜单搜索保持两次、失效实例清理回归。仅修改 Lua 和安装工具，未修改或替换原生 DLL。未将本轮验证记为原生重新编译通过。

安装：确认 Palworld 进程退出后，使用 `tools/install_ui_patch.ps1` 将单个 UI.lua 同步到当前 UE4SS 部署目录和 `G:/SteamLibrary/steamapps/workshop/content/1623730/3822215387/`。两处哈希均与源码一致；更新本机包哈希记录，保留 `.workshop.json`、配置、预设和 DLL。原文件备份至 `G:/SteamLibrary/steamapps/common/Palworld/Mods/_LocalBackups/CustomPresets-ui-performance-20261019-133504/`。未下载或发布云端工坊版本。

真实 UI：Palworld 1.0.5.102999 完整重启后，通过 computer-use 实际点击主菜单 → 开始游戏 → 创建新世界 → 自定义设置，等待后确认底部“未选择预设／添加为新预设”控件出现。点击原生确定返回上层，再取消返回世界列表，未创建新世界、未应用或保存预设。日志出现 `Preset action row attached above original confirm`，本轮检查未见 `Error:`。日志证据为 `.build/custom-presets-performance-20261019/startup.log` 和 `ui-check.log`；画面见本次聊天的 computer-use 工具结果。

未验证：本轮人物编辑界面、手柄导航、多次打开和长时间游玩尚未实机重测；未采集优化前后帧时间，不能宣称具体 FPS 提升。之前功能的离线回归不等同于本轮全部真实界面验证。

## 工坊更新 1.0.1（2026-10-19）

按用户授权发布至原条目 `3822215387`。四语版本与更新说明从本地化 README 生成，使用已有经导入审核的 DLL；打包通过，上传前核对生成包与工坊本地包清单全部文件哈希一致。Steam SDK 上传返回成功，四语标题／正文已读回核对，公开状态、依赖和封面保持一致；未重新下载远端内容，因此上传校验不记为下载文件验收。发布包 `dist/workshop-custom-presets-1.0.1-20261019/CustomPresets/`，发布证据 `.build/workshop-custom-presets-1.0.1-20261019/progress.json` 与 `after.json`。本次未提交 Git。
