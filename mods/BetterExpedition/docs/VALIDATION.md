# 十倍速度精简版验收

## 当前范围（2026-10-19）

用户指定仅保留缩短时间，耗时为原版 10%。原版 1.0.5.102999 数据表解码基线来自 `.build/inspect-easy-expedition-20261018/original-decoded.json`；不是游戏源码。18 项任务只覆盖 RequiredSeconds，保留战力、研究、解锁、奖励、经验与原生完成／取消流程。已派遣任务的保存时间不追溯改写。

旧版源码、测试、构建及验收记录位于 `../archive/manual-expeditions/`，仅为历史证据，不代表当前精简版已通过实机验收。旧版性能根因未确认。

## 待实机验证

冷启动加载、选择页预览及真实派遣耗时、战力／研究加成、自动完成后实际奖励与经验、取消不领奖、返回与再次派遣、重启保存、锁定／部分解锁，以及同场景性能。联机客户端和专用服务器未验证。当前未使用接口测试代替真实 UI 验收。

## 本次已执行

- 离线：18 个任务与原版解码基线逐项核对，基础时间全部为 10%，只修改 RequiredSeconds；运行目录不含可执行脚本或 DLL。专用检查与统一构建入口通过。
- 安装：确认游戏进程未运行后，通过安装脚本安装至 `G:/SteamLibrary/steamapps/common/Palworld/Mods/NativeMods/UE4SS/Mods/PalSchema/mods/BetterExpedition`，文件 SHA-256 校验一致；旧 UE4SS BetterExpedition 安装目录不存在。PalSchema 本地版本记录为 0.6.7。未切换 Workshop。
- 启动尝试：computer-use 分别启动根目录启动器和 Shipping 程序，均返回“launched app did not expose a targetable window”；再次枚举未发现游戏窗口，不能宣称冷启动或加载成功。未进入存档、未试发奖励。
- 共享工具回归：29 项运行，28 项通过；`test_packages_deploy_to_expected_runtime_layout` 因 Workshop 元数据版本断言预期 1.0.0、实际 1.0.1 失败。该项未验证远征补丁，不为通过测试更改其他 mod 版本。
