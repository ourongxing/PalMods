# Better Expedition / 更好的远征

当前仅缩短远征时间：全部 18 个原版任务的基础耗时降为 10%（十倍速度），继续沿用原版战力与研究耗时加成。基础 30／45／60／120 分钟分别变为 3／4.5／6／12 分钟。

从原版入口选择任务、派遣、等待自动完成，再通过原版奖励容器领取。解锁、组队、奖励、经验、取消、返回及保存流程保持原版规则；取消不会额外结算奖励。已派遣任务保存的完成时间不追溯修改，建议下一次派遣验证效果。

依赖已安装的 PalSchema，使用数据表补丁，不加载本 mod 的 Lua、DLL、HUD 或轮询。不要与其他修改同一任务 RequiredSeconds 的补丁叠加。当前数据基线为 Palworld 1.0.5.102999；新增任务需要补充数据。单机、房主及服务器的实际效果尚待本版本实机确认；客户端单独安装不承诺改变服务器计时。

构建：`python tools/build.py BetterExpedition`。检查：`python mods/BetterExpedition/tests/run.py`。关闭游戏后运行 `mods/BetterExpedition/tools/install_local.ps1`，继续使用本地安装，不切换 Workshop。

持续远征、手动结束、按时间比例结算与数字 HUD 已完整归档至 [archive/manual-expeditions](archive/manual-expeditions/README.md)，不参与当前构建或安装。旧版严重掉帧的根因尚未确认，归档不代表已修复。

验证范围见 [验收记录](docs/VALIDATION.md)。
