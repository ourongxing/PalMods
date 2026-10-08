Updraft Elevator

解锁：第9级古代科技，消耗1个古代科技点，解锁全部三种尺寸。
材料：每种需要10帕鲁矿碎片、30石头、3古代文明部件。
使用：按B，在基础设施／其他建造。在气流区域内按跳跃键，播放原版气流的起跳准备动画后升空。
拆除：进入拆除模式，瞄准气流下部。

高度配置：Mods/UpdraftElevator/Scripts/config.lua
Small / Medium / Large 对应小 / 中 / 大型，单位为米。
默认8 / 16 / 32，支持0.1～1000及小数。保存后重启游戏生效。
无效数值使用默认值；升级保留已有配置。

安装：退出游戏后，将Mods文件夹合并到UE4SS的Mods目录。
旧版升级：先将 CodexWindNativeMenu/Scripts/config.lua 复制到新的 UpdraftElevator/Scripts/config.lua，再将旧 CodexWindNativeMenu 和 PalSchema/mods/WindNativePrototype 文件夹移出 Mods 目录，避免重复加载。
依赖：UE4SS、PalSchema。
