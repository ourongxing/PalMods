# 创意工坊打包

各 mod 有独立的 `mods/<Mod>/workshop/Info.json` 和 PNG 封面。
作者为 `ourongxing`；包名固定为源码目录名，首次发布后不要随意修改。
工坊包均以 `1.0.0` 首次发布，不提供历史开发版本的迁移或后向兼容。
封面可替换，但须与 `Thumbnail` 字段一致。

## Better Arena

2026-10-19：沿用 PublishedId `3822475613` 发布 `1.0.1` 掉帧修复：移除空闲时反复全局搜索菜单，缓存游戏实例，减少页面重复刷新。用户已确认本地修复后明显改善；本次发布前 Lua 回归、构建及打包通过，包内清单哈希与工坊本地上传目录逐文件一致。Steam SDK 上传成功，四语标题与正文已读回核对，依赖、封面、标签与公开状态不变。发布包为 `dist/workshop-better-arena-1.0.1-20261019/BetterArena/`，发布证据与原工坊本地包备份位于 `.build/workshop-better-arena-1.0.1-20261019/`；保留原 `.workshop.json` 并更新版本。本轮未重新下载远端包。

2026-10-19：工坊简繁中文介绍改用游戏内“青铜／青銅至传奇／傳奇”的段位名称，移除自行添加的“杯／盃”。四语标题与正文已读回核对，内容包 23 个文件、版本、封面、标签、依赖和公开状态保持不变；记录位于 `.build/workshop-better-arena-rank-names-20261019/`。

2026-10-19：`1.0.0` 已公开发布，PublishedId 为 [3822475613](https://steamcommunity.com/sharedfiles/filedetails/?id=3822475613)，依赖 UE4SSExperimentalPW 和 PalSchema，最低游戏修订号为实测的 `102999`。

- 正式目录：`G:/SteamLibrary/steamapps/workshop/content/1623730/3822475613/`，保留 `.workshop.json`。
- 已读回核对四语标题与介绍、公开状态、标签和两个依赖；远程封面 SHA-256 与源码一致。Steam 重新下载的 23 个包内文件哈希全部匹配。
- 本机已订阅并启用工坊版本；原本地 Lua 和 PalSchema 数据归档至 `Mods/_LocalBackups/BetterArena-workshop-3822475613-20261019/`。官方部署的 Lua、两份补丁和管理元数据与发布包一致，完整启动后加载正常。
- 发布包：`dist/workshop-better-arena-publish-20261019/BetterArena/`；发布及核对记录：`.build/workshop-better-arena-publish-20261019/`。

修改 `Scripts/config.lua` 后重启，进入世界后自动生成并核对倍率。依赖 PalSchema 自动重载，若原先关闭，首次运行自动开启后需再完整重启一次。工坊下载和冷启动校验不代替游戏内结算验收；后者见 Better Arena 验收记录。

## Custom Presets 发布记录

2026-10-19：沿用 PublishedId `3822215387` 发布 `1.0.1`，用菜单创建通知替代每 750 ms 的两次全局菜单搜索。四语源 README、包版本及更新说明同步，Steam SDK 上传成功并读回核对四语标题／正文，依赖、封面、公开状态与原条目一致。发布包为 `dist/workshop-custom-presets-1.0.1-20261019/CustomPresets/`，证据与原本地包备份位于 `.build/workshop-custom-presets-1.0.1-20261019/`。工坊本地目录保留原 `.workshop.json` 并更新发布版本；本次未重新下载远端内容，上传前已核对本地包全部清单哈希。

2026-10-18：`1.0.0` 已公开发布，PublishedId 为 `3822215387`，依赖 UE4SSExperimentalPW。

- 正式目录：`G:/SteamLibrary/steamapps/workshop/content/1623730/3822215387/`，保留 `.workshop.json`。
- 已读回核对四语标题、简介、封面、标签、依赖与公开状态；Steam 下载的 16 个文件哈希全部匹配。
- 发布包：`dist/workshop-custom-presets-concise-20261018/CustomPresets/`；发布记录：`.build/workshop-custom-presets-publish-20261018/`。
- 原本地测试目录 `3621570584` 已归档至 `Mods/_LocalBackups/CustomPresets-workshop-local-3621570584/`，避免重复加载。
- 用户数据位于 `%LOCALAPPDATA%/Pal/Saved/CustomPresets/presets/`：每个预设一个文件，人物另配缩略图，备份位于相邻 `backups/`。

下载校验不代替游戏内功能验收。

## 已发布条目

2026-10-18：BetterStorage、BetterWorkbench、BetterPalSouls 沿用现有 PublishedId 更新四语工坊文案，精简功能说明与配置说明，突出操作方式并保留兼容限制。12 份标题与描述已从 Steam 读回核对；版本、封面、标签、依赖、公开状态与本机工坊包文件保持不变。简介来源为 `dist/workshop-listings-copy-20261018-v2/`，发布及核对记录位于 `.build/workshop-copy-update-20261018/`。

2026-10-18：上述 9 个已发布条目沿用原 PublishedId 更新为统一风格的新封面，QuickButcher 使用用户提供的岩甲帕鲁形象。通过 Steam SDK 仅设置页面预览图，未上传内容包或修改版本；四语标题与描述、标签、依赖、公开状态和本机工坊包全部保持不变。已读回 9 张远程预览图，SHA-256 均与源码 `workshop/thumbnail.png` 一致。上传与核对记录位于 `.build/workshop-cover-update-20261018/`。PalCombo 与 BetterBulkStorage 未在本次创建或发布条目。

2026-10-18：UpdraftElevator 沿用 `3820050074` 发布 `1.1.1`，保留客户端规则，新增专用服务器 Lua 与 PalSchema 安装规则。四语简介版本同步更新；公开状态、封面、标签和依赖已读回核对。已通过游戏 AppID 重新下载，17 个包内文件的 SHA-256 全部匹配，并确认四条安装规则。发布包位于 `dist/workshop-updraft-server-1.1.1-20261018/`，发布记录及旧工坊包备份位于 `.build/workshop-updraft-server-1.1.1-20261018/`。专用服务器内功能仍待实机验收。

2026-10-15：以下七个包以 `1.0.0` 发布，已从 Steam 读回核对四语标题与正文、公开可见性、标签、封面和前置依赖。

| 包名 | Workshop |
| --- | --- |
| AnywherePalBox | [3820048264](https://steamcommunity.com/sharedfiles/filedetails/?id=3820048264) |
| BetterPalSouls | [3820049739](https://steamcommunity.com/sharedfiles/filedetails/?id=3820049739) |
| BetterStorage | [3820049820](https://steamcommunity.com/sharedfiles/filedetails/?id=3820049820) |
| BetterWorkbench | [3820049890](https://steamcommunity.com/sharedfiles/filedetails/?id=3820049890) |
| ExtraImplantDrops | [3820049962](https://steamcommunity.com/sharedfiles/filedetails/?id=3820049962) |
| PointBlankBurstSkills | [3820050011](https://steamcommunity.com/sharedfiles/filedetails/?id=3820050011) |
| UpdraftElevator | [3820050074](https://steamcommunity.com/sharedfiles/filedetails/?id=3820050074) |
| CustomPresets | [3822215387](https://steamcommunity.com/sharedfiles/filedetails/?id=3822215387) |
| BetterArena | [3822475613](https://steamcommunity.com/sharedfiles/filedetails/?id=3822475613) |
| QuickButcher | [3821569615](https://steamcommunity.com/sharedfiles/filedetails/?id=3821569615) |

2026-10-17：QuickButcher（Quick Butcher / 快速肢解）以 `1.0.0` 首次公开发布，
四语标题／描述、标签、封面及无前置依赖已从 Steam 读回核对。通过游戏 AppID 下载后，
8 个包内文件的 SHA-256 全部匹配。发布包为 `dist/workshop-quickbutcher-publish-20261017/`，
发布与核对记录位于 `.build/workshop-quickbutcher-publish-20261017/`。
本机开发测试已切换到对应工坊目录；静态与下载校验不代替游戏内功能验收。

2026-10-16：UpdraftElevator、BetterStorage、PointBlankBurstSkills 沿用上述条目更新至 `1.1.0`，仅修正 PalSchema 安装目标的末尾斜杠并更新版本标记。脚本、DLL、建筑资源、封面及工坊四语标题／介绍、标签、依赖和可见性保持不变。已通过 Steam 游戏端重新下载三包并逐文件核对 SHA-256；发布记录位于 `.build/workshop-update-1.1.0-20261016/`，上传包位于 `dist/workshop-install-fix-1.1.0-20261016/`。

2026-10-17：上述七个已发布条目的四语标题与描述已更新并从 Steam 读回核对。非英语标题统一为
`英文名 / 对应语言名`，英语保留英文名；描述使用本地化 README 与四语公共反馈／开源模板生成。
未重新上传 mod 文件，版本、封面、标签、依赖和可见性保持不变；本地工坊文件 SHA-256 核对一致。
页面快照、更新进度与核对记录位于 `.build/workshop-localization-update-20261017/`，
简介来源为 `dist/workshop-listings-bilingual-titles-20261017/`。该次更新未包含 QuickButcher。

本次上传目录为 `dist/workshop-publish-20261015/`，上传用预览图压缩为 768 × 768 PNG、每张小于 1 MB，源码高清封面保留。首次使用原始大图上传曾返回 `k_EResultLimitExceeded`；压缩预览图后成功。后续上传也应检查预览图大小。

工具可继续从 `G:/SteamLibrary/steamapps/workshop/content/1623730/<PublishedId>/` 更新这些条目，各目录的 `.workshop.json` 已保存对应发布 ID 和上次版本。更新文件时沿用现有 ID，并提高 `Info.json.Version`，避免重复创建条目；只更新页面标题／描述时无需改变包版本或上传文件。

## 简繁中文、日英四语

包内仅保留四份玩家说明，分别为
`README.zh-Hans.md`、`README.zh-Hant.md`、`README.ja.md`、`README.en.md`。
四份玩家说明维护工坊标题与各 mod 的功能介绍；打包时自动生成 `listing.json`，可在发布时填写对应语言的页面。
README 第一段为 `# 标题`，第二段为 `版本 · 作者`，后续正文作为简介；生成时保留版本／作者行，并将 Markdown 标题、无序／有序列表、粗体和链接转换为 Steam BBCode，行内代码以粗体原样显示，保留段落与换行。
非英语工坊标题统一为 `英文名 / 对应语言名`，英文名以 `README.en.md` 标题为准；英语页面只保留英文名。
例如简体中文为 `Quick Butcher / 快速肢解`，日语为 `Quick Butcher / 高速解体`，英语为 `Quick Butcher`。
反馈要求、日志说明及 GPL-3.0／源码地址统一维护在 `tools/workshop/templates/`，生成简介和打包 README 时自动追加。
各 mod 的源 README 只写功能、安装、配置和自身兼容说明，不重复写公共结尾。
依赖 UE4SSExperimentalPW 的 mod 自动附带 UE4SS 日志要求；独立 PAK mod 不附带该要求。
包内四语 README 与 `listing.json` 使用同一份渲染结果，不维护或生成额外的 `README.md` 导航页。
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
只生成工坊简介、不读取构建产物时，运行 `python tools/package_workshop.py all --listings-only`，
输出为 `dist/workshop-listings/<Mod>/listing.json`；也可指定 mod 与 `--output-root`。
已有输出会拒绝覆盖；更新时使用新的 `--output-root`，以便保留上次发布包。
各 mod 的版本在各自模板中维护；`--version` 可临时统一覆盖本次所选包的版本。
发布新版本时必须改变 `Version`，否则官方加载器可能不会重新安装。

`MinRevision=82182` 来自官方模板和本机框架包，表示框架基线，不代表各 mod 已在该游戏版本测试通过。
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
| BetterStorage | `Scripts/`、`dlls/main.dll`、`enabled.txt`、`PalSchema/blueprints/storage.json` | Lua + PalSchema | UE4SSExperimentalPW、PalSchema |
| AnywherePalBox | `Scripts/`、`enabled.txt` | Lua | UE4SSExperimentalPW |
| BetterPalSouls | `Scripts/`、`enabled.txt` | Lua | UE4SSExperimentalPW |
| BetterArena | `Scripts/`、`enabled.txt`、`PalSchema/{raw,blueprints}/` | Lua + PalSchema | UE4SSExperimentalPW、PalSchema |
| UpdraftElevator | `Scripts/`、`enabled.txt`、`PalSchema/{buildings,paks}/` | Lua + PalSchema | UE4SSExperimentalPW、PalSchema |
| PointBlankBurstSkills | `PalSchema/raw/point_blank_burst_skills.json` | PalSchema | UE4SSExperimentalPW、PalSchema |
| CustomPresets | [3822215387](https://steamcommunity.com/sharedfiles/filedetails/?id=3822215387) |
| QuickButcher | `Paks/QuickButcher_P.pak` | Paks | 无 |

`Lua` 规则将选中的脚本、DLL、配置和启用标记部署到
`Mods/NativeMods/UE4SS/Mods/<PackageName>/`。
`PalSchema` 规则的目标必须写成 `./PalSchema/`，保留末尾斜杠以复制目录内容；省略斜杠会在安装目录中多套一层 `PalSchema/`，导致建筑和科技等数据未加载。包内该目录直接放 `raw/`、`buildings/`、`blueprints/`、`paks/` 等数据目录。
加载器使用包名部署到 `Mods/NativeMods/UE4SS/Mods/PalSchema/mods/<PackageName>/`，
包内不要再多套一层 `<PackageName>`。
上升气流使用构建暂存中的 Lua 和资源，保持生成的默认高度与建筑资源一致。
`Paks` 规则使用 `./Paks/`，将目录内容部署到 `Pal/Content/Paks/~WorkshopMods/<PackageName>/`。
QuickButcher 打包前检查 PAK 与 `build-audit.json` 的 SHA-256 一致；工坊验收时先移除
`Pal/Content/Paks/~mods/QuickButcher/QuickButcher_P.pak` 手动副本，避免重复加载。
BetterStorage 采用 BetterBulkStorage 的四语资料结构，保留原版同类物品收纳条件，另附设计图家具与新公会库存容量补丁；两者不能同时启用。
安装规则默认用于客户端；需要部署到专用服务器的内容须额外添加同类型、同目标且带 `"IsServer": true` 的规则，保留原客户端规则。打包器接受布尔值 `IsServer`，并对两端执行相同的路径与目录布局校验。
UpdraftElevator 的 `1.1.1` 包同时包含客户端和服务器的 Lua、PalSchema 规则，修复服务器未部署脚本及建筑／科技数据的问题；其他 mod 不随此次改动添加服务器规则。安装规则不代表多人功能已经通过实机验收。

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
