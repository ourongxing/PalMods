# 气流资源构建

环境要求：UE 5.1.1、VS 2022、repak 和 `requirements-dev.txt`，路径设置见 [根 README](../../../README.md)。
完整构建使用 `python tools/build.py UpdraftElevator`；单步诊断顺序如下：

```powershell
python mods/UpdraftElevator/tools/build_native.py
python mods/UpdraftElevator/tools/run_native_build.py
python mods/UpdraftElevator/tools/cook_native.py
python mods/UpdraftElevator/tools/package_native.py --stage-only
```

编辑器编译使用 UE 自带 .NET 6。蓝图生成读取 `data/variants.json` 和六张 `assets/T_Wind*.png`，创建 `native/Content/`。
`Source/Pal` 提供游戏 API 声明，特效 `/Game/Pal/Effect/Common/JumpSpot/NS_JumpSpot` 使用编辑器占位资源；原版动作 `/Game/Pal/Blueprint/Action/Common/BP_Action_JumpFromJumpSpot` 也使用编辑器占位蓝图；这些占位资产和 DLL 仅用于生成和 Cook，不进入发布包。

UE 缓存位于 `native/`；日志、备份、PAK 输入和暂存位于 `.build/UpdraftElevator/`，发布包位于 `dist/UpdraftElevator/`。
打包脚本的 `--stage-only` 生成安装包；省略时备份并安装，执行前退出游戏。

`tools/wind_data.py` 从 `data/building_template.json` 生成建筑和科技元数据。
建造菜单使用独立的 `CodexWindUpdraft` 显示分组。Lua 启动时在显示分类枚举的 MAX 项之前注册它，再由 PalSchema 读取建筑配置；已有分类的值保持不变。分组标题复用科技名称的四语翻译，通过 `GetBuildObjectUIDIsplayCategoryTextId` 的输出参数提供。
源贴图可通过 `tools/generate_wind_art.py` 重生成，需 numpy、Pillow 和 `C:/Windows/Fonts/bahnschrift.ttf`。
Schema 来源及许可见 [data/schema](../data/schema/README.md)。

## 原版起跳动作

建筑在可用时由 `WindJump` 子 Actor 组件创建一个仅有碰撞体的 `PalLevelGimmickJumpSpot` 子类；不可用时移除该子 Actor。进入／离开气流由原版的 `EventOnActorBeginOverlap`／`EventOnActorEndOverlap` 登记和清除角色跳跃修饰器。Lua 在这些事件之后按重叠范围选择最高档、设置高度速度，地图原有气流优先。角色移动组件的重力在重叠变化时读取。

按跳跃键后的资格检查、动作取消、动画播放、动画通知发射及动作结束均由游戏处理。引用 `BP_Action_JumpFromJumpSpot`，设置 `bPlayJumpPrepareMontage=true`；游戏动作使用 `AM_Player_Female_JumpFromJumpSpot` 和 `PlayerLaunchMontageNotifyName`。这里只引用原版资源，不打包动画副本，不另调 `LaunchCharacter`。

本机游戏二进制的静态调用链（RVA）：

- `PalCharacter::RequestJump` 的反射入口 `0x28A0D20` 经虚函数转入 `0x2E496E0`，先调用已登记修饰器的接口，无修饰器时走普通跳跃。
- 地图气流进入／离开重叠的反射入口 `0x2986390`／`0x2986460`，登记函数 `0x2FDB390` 最终写入角色的跳跃修饰器；离开重叠清除它。
- 原版气流接口在 `0x2FEFE60` 调用 `WriteDataToBlackboard`，在 `0x2FEFEBC` 调用动作组件播放原版动作。

编辑器只有游戏 API 声明，能够验证子 Actor、资源引用、碰撞及可用性切换，不能证明游戏动画实际播放。发布前还需在游戏里检查准备动作、通知时机、三档高度、离开／拆除气流后的普通跳跃。

2026-10-08：v10 已安装，用户确认游戏内原版起跳动作和动画效果正常。三档配置、重叠选择和退出／失效清理由离线回归及编辑器实例检查覆盖。
