# 工坊公共文案

`templates/README.<language>.md` 统一维护四语反馈要求、开源协议与源码链接。
`templates/UE4SS.<language>.md` 维护 UE4SS 日志要求及获取路径。

`tools/package_workshop.py` 在生成工坊简介和打包 README 时自动追加公共结尾。
元数据的 `Dependencies` 包含 `UE4SSExperimentalPW` 时，才将对应日志说明填入 `{{runtime_logs}}`。
独立 PAK mod 使用相同反馈／开源模板，不追加 UE4SS 日志说明。

各 mod 的 `workshop/README.<language>.md` 只维护标题、版本／作者及自身说明。
不要手动维护公共结尾或生成的 `listing.json`。
修改模板后，使用新的输出目录重新生成所有简介：

```powershell
python tools/package_workshop.py all --listings-only --output-root dist/workshop-listings-next
```
