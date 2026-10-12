param([string]$ModsDirectory)
$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
. (Join-Path $repoRoot 'tools/paths.ps1')
if (-not $ModsDirectory) { $ModsDirectory = (Get-PalModsGamePaths).ModsDirectory }
$ModsDirectory = (Resolve-Path -LiteralPath $ModsDirectory).Path
if (Get-Process -Name 'Palworld-Win64-Shipping' -ErrorAction SilentlyContinue) {
    throw 'Close Palworld before replacing mods.'
}
$stage = Join-Path $repoRoot 'dist/ExtraImplantDrops/ExtraImplantDrops'
$candidate = Join-Path $stage 'dlls/main.dll'
$audit = Get-Content -LiteralPath (Join-Path $repoRoot '.build/ExtraImplantDrops/import-audit.json') -Raw | ConvertFrom-Json
if ((Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant() -ne $audit.dll_sha256) {
    throw 'Candidate DLL differs from the verified build.'
}
$destination = Join-Path $ModsDirectory 'ExtraImplantDrops'
$legacyDirectory = Join-Path $ModsDirectory 'ButcherImplants'
$existingConfigPath = Join-Path $destination 'config.ini'
$sourceConfigPath = $existingConfigPath
if (-not (Test-Path -LiteralPath $sourceConfigPath)) {
    $sourceConfigPath = Join-Path $legacyDirectory 'config.ini'
}
$existingConfig = $null
if (Test-Path -LiteralPath $sourceConfigPath) {
    $existingConfig = Get-Content -LiteralPath $sourceConfigPath -Raw
    $existingConfig = [regex]::Replace($existingConfig, '(?m)^[ \t]*(?:Enabled|StackCount|MaxItemsPerPal)[ \t]*=[^\r\n]*(?:\r?\n|$)', '')
    $versionComment = Get-Content -LiteralPath (Join-Path $stage 'config.ini') -TotalCount 1
    $existingConfig = [regex]::Replace($existingConfig, '(?m)^; (?:ExtraImplantDrops|ButcherImplants)[^\r\n]*', $versionComment)
    if (-not [regex]::IsMatch($existingConfig, '(?m)^[ \t]*DropChance[ \t]*=')) {
        $chance = 0.5
        $legacy = [regex]::Match($existingConfig, '(?m)^[ \t]*DropChancePercent[ \t]*=[ \t]*([^\r\n]*)')
        $parsedPercent = 0.0
        if ($legacy.Success -and [double]::TryParse($legacy.Groups[1].Value.Trim(),
            [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$parsedPercent) -and $parsedPercent -ge 0 -and $parsedPercent -le 100) {
            $chance = $parsedPercent / 100.0
        }
        $chanceText = $chance.ToString('G', [System.Globalization.CultureInfo]::InvariantCulture)
        $existingConfig = [regex]::Replace($existingConfig, '(?m)^\[Harvest\][ \t]*\r?$', "[Harvest]`r`nDropChance=$chanceText")
    }
    $existingConfig = [regex]::Replace($existingConfig, '(?m)^[ \t]*DropChancePercent[ \t]*=[^\r\n]*(?:\r?\n|$)', '')
}
$old = Join-Path $ModsDirectory 'ImplantHarvest'
$control = Join-Path $ModsDirectory 'mods.txt'
$jsonControl = Join-Path $ModsDirectory 'mods.json'
$backup = Join-Path $repoRoot ('.build/install-backups/ExtraImplantDrops-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $backup | Out-Null
foreach ($path in @($old, $destination, $legacyDirectory, $control, $jsonControl)) {
    if (Test-Path -LiteralPath $path) { Copy-Item -LiteralPath $path -Destination $backup -Recurse }
}
$text = Get-Content -LiteralPath $control -Raw
$text = [regex]::Replace($text, '(?m)^[ \t]*ButcherImplants[ \t]*:[ \t]*[01][ \t]*(?:\r?\n|$)', '')
$oldEntries = [regex]::Matches($text, '(?m)^\s*ImplantHarvest\s*:\s*[01]\s*$')
if ($oldEntries.Count -gt 0) { $text = [regex]::Replace($text, '(?m)^\s*ImplantHarvest\s*:\s*[01]\s*$', 'ImplantHarvest : 0') }
else { $text += "`r`nImplantHarvest : 0`r`n" }
if ([regex]::IsMatch($text, '(?m)^\s*ExtraImplantDrops\s*:\s*[01]\s*$')) {
    $text = [regex]::Replace($text, '(?m)^\s*ExtraImplantDrops\s*:\s*[01]\s*$', 'ExtraImplantDrops : 1')
} else { $text += "`r`nExtraImplantDrops : 1`r`n" }
$jsonText = $null
if (Test-Path -LiteralPath $jsonControl) {
    $items = @(Get-Content -LiteralPath $jsonControl -Raw | ConvertFrom-Json | Where-Object mod_name -ne 'ButcherImplants')
    foreach ($item in $items) {
        if ($item.mod_name -eq 'ImplantHarvest') { $item.mod_enabled = $false }
        if ($item.mod_name -eq 'ExtraImplantDrops') { $item.mod_enabled = $true }
    }
    if (-not ($items | Where-Object mod_name -eq 'ExtraImplantDrops')) {
        $items += [pscustomobject]@{ mod_name = 'ExtraImplantDrops'; mod_enabled = $true }
    }
    $jsonText = ConvertTo-Json -InputObject $items -Depth 10
}
New-Item -ItemType Directory -Path $destination -Force | Out-Null
Get-ChildItem -LiteralPath $stage | Copy-Item -Destination $destination -Recurse -Force
if ($null -ne $existingConfig) {
    [System.IO.File]::WriteAllText($existingConfigPath, $existingConfig, [System.Text.UTF8Encoding]::new($false))
}
$oldMarker = Join-Path $old 'enabled.txt'
if (Test-Path -LiteralPath $oldMarker) {
    # A single marker file is moved to the already-created backup; never remove the old mod.
    Move-Item -LiteralPath $oldMarker -Destination (Join-Path $backup 'ImplantHarvest-enabled.txt')
}
[System.IO.File]::WriteAllText($control, $text, [System.Text.UTF8Encoding]::new($false))
if ($null -ne $jsonText) {
    [System.IO.File]::WriteAllText($jsonControl, $jsonText + "`r`n", [System.Text.UTF8Encoding]::new($false))
}
if (Test-Path -LiteralPath $legacyDirectory) {
    $resolvedLegacy = (Resolve-Path -LiteralPath $legacyDirectory).Path
    $expectedLegacy = [System.IO.Path]::GetFullPath((Join-Path $ModsDirectory 'ButcherImplants'))
    $savedLegacy = Join-Path $backup 'ButcherImplants'
    if ($resolvedLegacy -ne $expectedLegacy -or -not $resolvedLegacy.StartsWith($ModsDirectory + '\')) {
        throw 'Legacy mod path validation failed.'
    }
    foreach ($file in Get-ChildItem -LiteralPath $resolvedLegacy -Recurse -File) {
        $relative = $file.FullName.Substring($resolvedLegacy.Length + 1)
        $saved = Join-Path $savedLegacy $relative
        if (-not (Test-Path -LiteralPath $saved) -or
            (Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath $saved).Hash) {
            throw 'Legacy mod backup verification failed.'
        }
    }
    Remove-Item -LiteralPath $resolvedLegacy -Recurse -Force
}
$manifest = [ordered]@{
    old_mod = $old; renamed_mod = $legacyDirectory; new_mod = $destination; backup = $backup
    installed_dll_sha256 = (Get-FileHash -LiteralPath (Join-Path $destination 'dlls/main.dll')).Hash.ToLowerInvariant()
    old_enabled = $false; new_enabled = $true
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backup 'installation.json') -Encoding utf8
Write-Output "Installed ExtraImplantDrops; renamed version backed up and removed; ImplantHarvest disabled. Backup: $backup"
