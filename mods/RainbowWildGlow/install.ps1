param([string]$GameRoot = 'G:\SteamLibrary\steamapps\common\Palworld')
$ErrorActionPreference = 'Stop'
if (Get-Process -Name 'Palworld-Win64-Shipping' -ErrorAction SilentlyContinue) {
    throw '请先退出帕鲁，再运行安装脚本。'
}
$ueMods = Join-Path $GameRoot 'Mods\NativeMods\UE4SS\Mods'
if (-not (Test-Path -LiteralPath $ueMods)) { throw '未找到工坊 UE4SS Mods 目录。' }
$target = Join-Path $ueMods 'RainbowWildGlow'
$oldPak = Join-Path $GameRoot 'Pal\Content\Paks\~mods\RainbowPassiveGlow\RainbowPassiveGlow_P.pak'
$backupDir = Join-Path $PSScriptRoot '..\..\.build\RainbowWildGlow\backup'
if (Test-Path -LiteralPath $target) {
    $snapshot = Join-Path $backupDir ('installed-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Path $snapshot -Force | Out-Null
    Copy-Item -LiteralPath $target -Destination $snapshot -Recurse
}
if (Test-Path -LiteralPath $oldPak) {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    $backup = Join-Path $backupDir 'RainbowPassiveGlow_P.pak'
    Copy-Item -LiteralPath $oldPak -Destination $backup -Force
    if ((Get-FileHash -LiteralPath $oldPak).Hash -ne (Get-FileHash -LiteralPath $backup).Hash) {
        throw '旧 Pak 备份校验失败。'
    }
    Remove-Item -LiteralPath $oldPak
}
New-Item -ItemType Directory -Path "$target\Scripts" -Force | Out-Null
foreach ($name in @('main.lua', 'config.lua')) {
    $source = Join-Path $PSScriptRoot "mod\Scripts\$name"
    $dest = Join-Path $target "Scripts\$name"
    # 更新代码时保留用户设置；默认配置只用于首次安装。
    if ($name -eq 'config.lua' -and (Test-Path -LiteralPath $dest)) {
        Write-Output 'Preserved existing RainbowWildGlow config.lua.'
        continue
    }
    Copy-Item -LiteralPath $source -Destination $dest -Force
    if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $dest).Hash) {
        throw "安装文件校验失败：$name"
    }
}
New-Item -ItemType File -Path "$target\enabled.txt" -Force | Out-Null
if (Test-Path -LiteralPath "$target\dlls") {
    # UE4SS treats the presence of dlls/ as a native mod, even with no active DLL.
    $modRoot = [IO.Path]::GetFullPath($target).TrimEnd('\') + '\'
    $legacyDlls = [IO.Path]::GetFullPath((Join-Path $target 'dlls'))
    $retiredDlls = [IO.Path]::GetFullPath((Join-Path $target ('retired-native-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))))
    if (-not $legacyDlls.StartsWith($modRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not $retiredDlls.StartsWith($modRoot, [StringComparison]::OrdinalIgnoreCase)) { throw '旧 Native 目录超出 Mod 路径。' }
    Move-Item -LiteralPath $legacyDlls -Destination $retiredDlls
}
$pakTarget = Join-Path $GameRoot 'Pal\Content\Paks\~mods\RainbowWildGlowAsset'
if (Test-Path -LiteralPath "$pakTarget\RainbowWildGlowAsset_P.pak") {
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    $pakBackup = Join-Path $backupDir ('private-asset-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.pak')
    Copy-Item -LiteralPath "$pakTarget\RainbowWildGlowAsset_P.pak" -Destination $pakBackup
    if ((Get-FileHash -LiteralPath "$pakTarget\RainbowWildGlowAsset_P.pak").Hash -ne (Get-FileHash -LiteralPath $pakBackup).Hash) {
        throw '旧私有 Pak 备份校验失败。'
    }
    Remove-Item -LiteralPath "$pakTarget\RainbowWildGlowAsset_P.pak"
}
$loadOrder = Join-Path $ueMods 'mods.txt'
$lines = if (Test-Path -LiteralPath $loadOrder) { @(Get-Content -LiteralPath $loadOrder) } else { @() }
$lines = @($lines | Where-Object { $_ -notmatch '^\s*RainbowWildGlow\s*:' })
$lines += 'RainbowWildGlow : 1'
[IO.File]::WriteAllLines($loadOrder, [string[]]$lines, [Text.UTF8Encoding]::new($false))
Write-Output 'RainbowWildGlow 0.9.9 installed. Restart Palworld.'
