# 创意工坊打包

五个 mod 各有独立的 `mods/<Mod>/workshop/Info.json` 和 PNG 封面。
作者为 `ourongxing`；包名固定为源码目录名，首次发布后不要随意修改。
五个工坊包均以 `1.0.0` 首次发布，不提供历史开发版本的迁移或后向兼容。
封面可替换，但须与 `Thumbnail` 字段一致。

## 简繁中文、日英四语

包内 `README.md` 提供简体中文、繁體中文、日本語、English 入口；四份玩家说明分别为
`README.zh-Hans.md`、`README.zh-Hant.md`、`README.ja.md`、`README.en.md`。
各模板的 `listing.json` 保存四种语言的工坊标题与介绍，可在发布时填写对应语言的页面。
`listing.json` 是本仓库的发布素材，不是官方加载器的语言字段；`Info.json.ModName` 只保留英文与简体中文标题（英文 / 简体中文）。

BetterWorkbench 分解界面的新增文字通过 Unreal 的 `GetCurrentLanguage()` 跟随游戏语言，
支持区域语言标签，其他语言或读取失败时回退英文。
繁体中文可自动识别 `zh-Hant`、`zh-TW`、`zh-HK`、`zh-MO`；显式简繁标签优先于地区。
可在 `Scripts/config.lua` 中使用 `Disassembly.Language = "zh-Hans"`、`"zh-Hant"`、`"ja"` 或 `"en"` 覆盖自动选择。
物品名仍由游戏的 `PalUIUtility:GetItemName` 读取，以保留官方翻译。

上升气流使用 PalSchema 的 `translations/zh-Hans`、`translations/zh-Hant`、`translations/ja`、`translations/en`，
`translations/global` 提供英文后备。建筑元数据不再写全语言覆盖的 Name/Description。
PalCombo、PointBlankBurstSkills 与 BetterBulkStorage 不新增游戏内 UI 文字，原有名称由游戏负责本地化。
修改语言后重新启动游戏，让 PalSchema 重新加载对应语言表。

技能和物品术语沿用已有游戏译名；新增功能和上升气流名称为本 mod 自行撰写的自然表达。
日语技能名参考游戏数据镜像：[ボルカニックレイン](https://paldb.cc/ja/Volcanic_Rain)、
[ロックバースト](https://paldb.cc/ja/Rockburst)、[ポイズンシャワー](https://paldb.cc/ja/Poison_Shower)。
该镜像不是官方站点；游戏内名称优先直接读取游戏，发布说明可随实机核对更新。
语言表格式和行名依据 [PalSchema 语言文档](https://okaetsu.github.io/PalSchema/docs/guides/translations/intro)
及 [建筑加载器源码](https://github.com/Okaetsu/PalSchema/blob/main/src/Loader/PalBuildingModLoader.cpp)。
繁体技能术语参考：[熔岩爆發](https://paldb.cc/tw/Volcanic_Rain)、
[岩爆](https://paldb.cc/tw/Rockburst)、[毒雨](https://paldb.cc/tw/Poison_Shower)。

BetterBulkStorage 的原版功能名称已按官方 v0.6.0 公告的四语正文核对：
简体中文「批量快速收纳」、繁体中文「批量快速收納」、日语「一括便利収納」、英语「Easy Bulk Storage」。
官方 Steam 公告数据：[简体中文](https://store.steampowered.com/events/ajaxgetpartnerevent?appid=1623730&announcement_gid=518590951147438123&lang_list=6)、
[繁体中文](https://store.steampowered.com/events/ajaxgetpartnerevent?appid=1623730&announcement_gid=518590951147438123&lang_list=7)、
[日语](https://store.steampowered.com/events/ajaxgetpartnerevent?appid=1623730&announcement_gid=518590951147438123&lang_list=10)、
[英语](https://store.steampowered.com/events/ajaxgetpartnerevent?appid=1623730&announcement_gid=518590951147438123&lang_list=0)。
mod 标题和「主据点」为本 mod 的表达；「主据点」指所属公会中建筑物最多的据点，同数时选择最近的。
工坊介绍保留手动触发的原版入口，不宣称后台自动收纳或额外的箱子命名识别规则。

## 生成包

先按根 README 构建需要发布的 mod，再在仓库根目录运行：

```powershell
python tools/package_workshop.py all
python tools/package_workshop.py PalCombo PointBlankBurstSkills --output-root dist/workshop-next
python tools/package_workshop.py all --author ourongxing --min-revision 82182 --output-root dist/workshop-review
```

无参数等同于 `all`。脚本使用已有构建产物，不编译、不安装、不创建 Steam 条目、不上传。
默认输出 `dist/workshop/<Mod>/` 及 `dist/workshop/<Mod>.zip`，ZIP 根目录直接包含 `Info.json`。
已有输出会拒绝覆盖；更新时使用新的 `--output-root`，以便保留上次发布包。
各 mod 的版本在各自模板中维护；`--version` 可临时统一覆盖本次所选包的版本。
发布新版本时必须改变 `Version`，否则官方加载器可能不会重新安装。

`MinRevision=82182` 来自官方模板和本机框架包，表示框架基线，不代表五个 mod 已在该游戏版本测试通过。
正式发布前应根据实机验证填写最低支持修订号（游戏标题版本号的最后五位）。
三个原生 mod 还要求匹配的 UE4SS ABI；该字段只检查游戏最低修订号，不能保证 DLL 兼容性。
BetterWorkbench 打包时会检查 DLL 与 `import-audit.json` 的哈希和导入审核数量；
此脚本生成的是待验收工坊包，不替代原有候选发布脚本的 `validation.json` 验收要求。

## 文件与安装规则

| 包名 | 包内布局 | 安装规则 | 依赖包名 |
| --- | --- | --- | --- |
| BetterWorkbench | `Scripts/`、`dlls/main.dll`、`enabled.txt` | Lua | UE4SSExperimentalPW |
| PalCombo | `Scripts/`、`dlls/main.dll`、`config.ini`、`enabled.txt` | Lua | UE4SSExperimentalPW |
| BetterBulkStorage | `Scripts/`、`dlls/main.dll`、`enabled.txt` | Lua | UE4SSExperimentalPW |
| UpdraftElevator | `Scripts/`、`enabled.txt`、`PalSchema/{buildings,paks}/` | Lua + PalSchema | UE4SSExperimentalPW、PalSchema |
| PointBlankBurstSkills | `PalSchema/raw/point_blank_burst_skills.json` | PalSchema | UE4SSExperimentalPW、PalSchema |

`Lua` 规则将选中的脚本、DLL、配置和启用标记部署到
`Mods/NativeMods/UE4SS/Mods/<PackageName>/`。
`PalSchema` 规则选中包内 `PalSchema/`，其中直接放 `raw/`、`buildings/`、`paks/` 等数据目录。
加载器使用包名部署到 `Mods/NativeMods/UE4SS/Mods/PalSchema/mods/<PackageName>/`，
包内不要再多套一层 `<PackageName>`。
上升气流使用构建暂存中的 Lua 和资源，保持生成的默认高度与建筑资源一致。
所有规则目前仅用于游戏客户端，未声明专用服务器支持。

发布包不含框架本体、SDK、源码工程、`mods.txt`、本机 `Jobs`、存档或日志。
`enabled.txt` 仅启用自己的 UE4SS mod，不覆盖用户的全局启用列表。
每个包附带 README 和 `package-manifest.json`，后者记录文件 SHA-256，方便核对发布内容。
PalCombo 随包保留已有 LICENSE。

## 导入官方上传工具

1. 在 Palworld Mod Uploader 中按住 Shift 创建本地测试包，不注册 Steam 条目。
2. 将生成的 `<Mod>/` 中全部文件复制到工具创建的包目录，替换模板 `Info.json`，重新加载。
3. 在游戏 Mod Management 中检查识别、依赖及启用情况，再做实际功能验收。
4. 正式发布时，用普通 Create New Mod 创建条目，把已验收内容复制过去。
   保留工具创建的 `.workshop.json`，以后更新同一个条目。

本机已有手动安装副本和 `CloseRangeBurstSkills` 旧目录，工坊验收前应处理旧副本，避免重复加载。
配置、BetterWorkbench Jobs 的升级保留及卸载行为仍需在工坊流程中另行测试。

官方参考：

- [包格式](https://github.com/pocketpairjp/PalworldModUploader/blob/main/PalworldModUploader/docs/en/02-Package.md)
- [上传工具](https://github.com/pocketpairjp/PalworldModUploader/blob/main/PalworldModUploader/docs/en/03-ModUploader.md)
- [安装规则与版本更新](https://github.com/pocketpairjp/PalworldModUploader/blob/main/PalworldModUploader/docs/en/04-Tech.md)
