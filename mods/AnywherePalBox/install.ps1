param([string]$GameRoot = 'G:\SteamLibrary\steamapps\common\Palworld')
$ErrorActionPreference = 'Stop'
if (Get-Process -Name 'Palworld-Win64-Shipping' -ErrorAction SilentlyContinue) {
    throw '请先退出帕鲁，再运行安装脚本。'
}
$ueMods = Join-Path $GameRoot 'Mods\NativeMods\UE4SS\Mods'
if (-not (Test-Path -LiteralPath $ueMods)) { throw '未找到 UE4SS Mods 目录。' }
$target = Join-Path $ueMods 'AnywherePalBox'
if (Test-Path -LiteralPath $target) {
    $snapshot = Join-Path $PSScriptRoot ('..\..\.build\AnywherePalBox\backup\installed-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $snapshot -Force | Out-Null
    Copy-Item -LiteralPath $target -Destination $snapshot -Recurse
}
New-Item -ItemType Directory -Path (Join-Path $target 'Scripts') -Force | Out-Null
foreach ($relative in @('Scripts\main.lua', 'enabled.txt')) {
    $source = Join-Path $PSScriptRoot (Join-Path 'mod' $relative)
    $dest = Join-Path $target $relative
    Copy-Item -LiteralPath $source -Destination $dest -Force
    if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $dest).Hash) {
        throw "安装文件校验失败：$relative"
    }
}
$config = Join-Path $target 'Scripts\config.lua'
if (-not (Test-Path -LiteralPath $config)) {
    $source = Join-Path $PSScriptRoot 'mod\Scripts\config.lua'
    Copy-Item -LiteralPath $source -Destination $config
    if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $config).Hash) {
        throw '安装文件校验失败：Scripts\config.lua'
    }
}
foreach ($relative in @('Scripts\gamepad.lua')) {
    $obsolete = Join-Path $target $relative
    if (Test-Path -LiteralPath $obsolete) { Remove-Item -LiteralPath $obsolete }
}
$loadOrder = Join-Path $ueMods 'mods.txt'
$lines = if (Test-Path -LiteralPath $loadOrder) { @(Get-Content -LiteralPath $loadOrder) } else { @() }
$lines = @($lines | Where-Object { $_ -notmatch '^\s*AnywherePalBox\s*:' })
$lines += 'AnywherePalBox : 1'
[IO.File]::WriteAllLines($loadOrder, [string[]]$lines, [Text.UTF8Encoding]::new($false))
Write-Output 'AnywherePalBox 1.0.0 installed. Set Hotkey in Scripts\config.lua, then restart Palworld (default: K).'
