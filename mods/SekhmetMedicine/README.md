# Sekhmet Medicine / 制药的塞赫麦特

仅为头目塞赫麦特增加基础制药 3 级，直接获得，无需先吃书。普通塞赫麦特不变。
只修改 `BOSS_Sekhmet` 数据行的 `WorkSuitability_ProductMedicine` 字段。
原版手工、采矿、搬运、战斗和伙伴技能保持原值。

依赖现有 UE4SS 与 PalSchema。适用于本机当前游戏数据；更新游戏后应重新核对。
该补丁按物种生效，不限定某一只个体。联机客户端和专用服务器尚未验证。

构建：`python tools/build.py SekhmetMedicine`。
游戏完全退出后运行 `mods/SekhmetMedicine/tools/install_local.ps1` 安装，随后完整启动。
本地目录：`<Palworld>/Mods/NativeMods/UE4SS/Mods/PalSchema/mods/SekhmetMedicine/`。
卸载时先退出游戏，再移除此目录；不会主动清除存档中已获得的强化。

验证进度见 [docs/VALIDATION.md](docs/VALIDATION.md)。
