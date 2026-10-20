param([string]$GameRoot = 'G:/SteamLibrary/steamapps/common/Palworld', [switch]$ResetConfig,
      [switch]$PerformancePatchOnly)
$ErrorActionPreference = 'Stop'
if (Get-Process -Name 'Palworld','Palworld-Win64-Shipping','PalServer','PalServer-Win64-Shipping-Cmd','PalServer-Win64-Shipping' -ErrorAction SilentlyContinue) {
    throw 'Close Palworld before installing BetterArena.'
}
$source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../mod'))
$destination = Join-Path $GameRoot 'Mods/NativeMods/UE4SS/Mods/BetterArena'
if (Test-Path -LiteralPath $destination) {
    $backup = Join-Path $GameRoot ('Mods/_LocalBackups/BetterArena-before-install-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Split-Path -Parent $backup) -Force | Out-Null
    Copy-Item -LiteralPath $destination -Destination $backup -Recurse
    Write-Output "Runtime backup: $backup"
}
if ($PerformancePatchOnly) {
    # Keep the existing Workshop installation and config; patch only the two
    # runtime modules being tested, with rollback copies outside load paths.
    $workshop = 'G:/SteamLibrary/steamapps/workshop/content/1623730/3822475613'
    $backup = Join-Path $GameRoot ('Mods/_LocalBackups/BetterArena-performance-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $targets = @($destination)
    if (Test-Path -LiteralPath (Join-Path $workshop '.workshop.json')) { $targets += $workshop }
    foreach ($targetRoot in $targets) {
        if (-not (Test-Path -LiteralPath (Join-Path $targetRoot 'Scripts/BetterArena/UI.lua'))) {
            throw "Existing BetterArena installation not found: $targetRoot"
        }
    }
    for ($i = 0; $i -lt $targets.Count; $i++) {
        foreach ($name in @('UI.lua', 'Balance.lua')) {
            $relative = 'Scripts/BetterArena/' + $name
            $target = Join-Path $targets[$i] $relative
            $saved = Join-Path $backup ("$i/" + $relative)
            New-Item -ItemType Directory -Path (Split-Path -Parent $saved) -Force | Out-Null
            Copy-Item -LiteralPath $target -Destination $saved
            Copy-Item -LiteralPath (Join-Path $source $relative) -Destination $target -Force
        }
        $manifestPath = Join-Path $targets[$i] 'package-manifest.json'
        if (Test-Path -LiteralPath $manifestPath) {
            Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $backup "$i/package-manifest.json")
            $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            foreach ($name in @('UI.lua', 'Balance.lua')) {
                $relative = 'Scripts/BetterArena/' + $name
                $manifest.Files.$relative = (Get-FileHash -LiteralPath (Join-Path $targets[$i] $relative) -Algorithm SHA256).Hash.ToLowerInvariant()
            }
            $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding utf8
        }
    }
    Write-Output "Installed performance patch. Backup: $backup"
    return
}
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
