param([string]$GameRoot = 'G:/SteamLibrary/steamapps/common/Palworld', [switch]$ResetConfig)
$ErrorActionPreference = 'Stop'
if (Get-Process 'Palworld-Win64-Shipping' -ErrorAction SilentlyContinue) {
    throw 'Close Palworld before installing BetterArena.'
}
$source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../mod'))
$destination = Join-Path $GameRoot 'Mods/NativeMods/UE4SS/Mods/BetterArena'
if (-not (Test-Path (Join-Path $GameRoot 'Mods/NativeMods/UE4SS/UE4SS.dll'))) {
    throw 'The local UE4SS installation was not found.'
}
if (-not (Test-Path (Join-Path $GameRoot 'Mods/NativeMods/UE4SS/Mods/PalSchema/dlls/main.dll'))) {
    throw 'BetterArena requires the existing local PalSchema installation.'
}
New-Item -ItemType Directory -Path $destination -Force | Out-Null
Get-ChildItem -LiteralPath $source -File -Recurse | ForEach-Object {
    $relative = $_.FullName.Substring($source.Length + 1)
    $target = Join-Path $destination $relative
    if ($relative.Replace('\', '/') -eq 'Scripts/config.lua' -and (Test-Path -LiteralPath $target) -and -not $ResetConfig) {
        Write-Output 'Preserved Scripts/config.lua.'
    } else {
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath $_.FullName -Destination $target -Force
    }
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../README.md') -Destination $destination -Force
$schemaConfigPath = Join-Path $GameRoot 'Mods/NativeMods/UE4SS/Mods/PalSchema/config/config.json'
$schemaConfig = [IO.File]::ReadAllText($schemaConfigPath)
if ($schemaConfig -match '"enableAutoReload"\s*:\s*false') {
    if (-not (Test-Path -LiteralPath ($schemaConfigPath + '.before-better-arena'))) {
        Copy-Item -LiteralPath $schemaConfigPath -Destination ($schemaConfigPath + '.before-better-arena')
    }
    $schemaConfig = [regex]::Replace($schemaConfig, '("enableAutoReload"\s*:\s*)false', '${1}true')
    [IO.File]::WriteAllText($schemaConfigPath, $schemaConfig, (New-Object System.Text.UTF8Encoding($false)))
}
# Create the mod-owned patch directories and ship an initial default patch.
# Lua regenerates their contents from config.lua when a world starts.
$schemaDestination = Join-Path $GameRoot 'Mods/NativeMods/UE4SS/Mods/PalSchema/mods/BetterArena'
$schemaBuild = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../.build/BetterArena/schema'))
foreach ($relative in @('raw/arena_rewards.json','blueprints/arena_points.json')) {
    $target = Join-Path $schemaDestination $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $schemaBuild $relative) -Destination $target -Force
}
New-Item -ItemType Directory -Path (Join-Path $env:LOCALAPPDATA 'Pal/Saved/BetterArena') -Force | Out-Null
Write-Output "Installed BetterArena to $destination"
