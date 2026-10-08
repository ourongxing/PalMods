# PalCombo 实现与调试

原生模块为玩家 Otomo 战斗动作替换技能槽选择结果，保留原选择器的副作用。
连招状态按帕鲁保存，以技能实际进入冷却作为推进条件；同一动作切换中的重复选择返回同一槽。
目标变化时重置待选状态。默认提前窗口为 3 秒，用户配置见 [README](../README.md)。

## 冷却与状态

`GetCoolTime` 返回已流逝冷却时间，`GetCoolTimeRate` 返回已流逝比例。
两者为正有限值时，剩余秒数为 `elapsed * (1 - rate) / rate`。
曾观察到两次选择调用仅间隔 0.00024 秒；状态必须在冷却开始后推进，才能避免跳过第一技能。

## Hook 边界

调用链见 [DECOMPILATION.md](DECOMPILATION.md)。战斗动作直接调用 C++ 选择器，UFunction Hook 无法覆盖该路径。
安装前核对选择器前 15 字节和直接调用目标；未知二进制记录 `unsupported game binary`。
同步 `CancelAction` 会递归触发 `StartNextAction_Event`，因此选择器只替换返回槽位。

## 验证与排查

纯连招回归在 `tests/native/rotation_test.cpp`，通过 `python tools/test.py` 运行。
DLL 编译和纯逻辑回归已通过，当前连招的游戏效果仍需验证。

未命中选择器时检查有界诊断和 `SelfActor` 所属控制器；选择日志正确而实际施放不同技能时，
继续追踪 `NextActionClass` 赋值与 `StartNextAction_Event` 分发。
