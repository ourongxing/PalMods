param([string]$GameRoot = 'G:/SteamLibrary/steamapps/common/Palworld',
      [string]$WorkshopRoot = 'G:/SteamLibrary/steamapps/workshop/content/1623730/3822215387')
$ErrorActionPreference = 'Stop'
if (Get-Process '*Palworld*' -ErrorAction SilentlyContinue) { throw 'Close Palworld before installing the CustomPresets UI patch.' }
$source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../mod/Scripts/CustomPresets/UI.lua'))
$runtime = Join-Path $GameRoot 'Mods/NativeMods/UE4SS/Mods/CustomPresets'
$targets = @($runtime, $WorkshopRoot)
foreach ($root in $targets) {
    if (-not (Test-Path -LiteralPath (Join-Path $root 'Scripts/CustomPresets/UI.lua'))) { throw "Existing installation not found: $root" }
}
$backup = Join-Path $GameRoot ('Mods/_LocalBackups/CustomPresets-ui-performance-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $backup | Out-Null
for ($i=0; $i -lt $targets.Count; $i++) {
    $target = Join-Path $targets[$i] 'Scripts/CustomPresets/UI.lua'
    Copy-Item -LiteralPath $target -Destination (Join-Path $backup "$i-UI.lua")
    Copy-Item -LiteralPath $source -Destination $target -Force
    $manifestPath = Join-Path $targets[$i] 'package-manifest.json'
    if (Test-Path -LiteralPath $manifestPath) {
        Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $backup "$i-package-manifest.json")
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.Files.'Scripts/CustomPresets/UI.lua' = (Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant()
        $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    }
    if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $target).Hash) { throw "Installed file differs: $target" }
}
Write-Output "CustomPresets UI patch installed and verified. Backup: $backup"
