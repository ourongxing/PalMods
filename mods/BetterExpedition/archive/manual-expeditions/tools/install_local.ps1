param([string]$GameRoot = 'G:/SteamLibrary/steamapps/common/Palworld')
$ErrorActionPreference = 'Stop'
if (Get-Process 'Palworld','Palworld-Win64-Shipping','PalServer-Win64-Shipping' -ErrorAction SilentlyContinue) {
    throw 'Close Palworld before installing BetterExpedition.'
}
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$source = Join-Path $root 'dist/BetterExpedition/BetterExpedition'
$destination = Join-Path $GameRoot 'Mods/NativeMods/UE4SS/Mods/BetterExpedition'
if (-not (Test-Path (Join-Path $source 'dlls/main.dll'))) { throw 'Build BetterExpedition first.' }
if (-not (Test-Path (Join-Path $GameRoot 'Mods/NativeMods/UE4SS/UE4SS.dll'))) { throw 'Local UE4SS not found.' }
if (Test-Path -LiteralPath $destination) {
    $backup = Join-Path $root ('.build/BetterExpedition/install-backups/' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    New-Item -ItemType Directory -Force $backup | Out-Null
    Copy-Item -LiteralPath $destination -Destination $backup -Recurse
}
New-Item -ItemType Directory -Force $destination | Out-Null
Get-ChildItem -LiteralPath $source -File -Recurse | ForEach-Object {
    $relative = $_.FullName.Substring($source.Length + 1)
    $target = Join-Path $destination $relative
    New-Item -ItemType Directory -Force (Split-Path -Parent $target) | Out-Null
    if (Test-Path -LiteralPath $target) {
        if ((Get-FileHash -LiteralPath $_.FullName).Hash -eq (Get-FileHash -LiteralPath $target).Hash) { return }
        # A closed crash reporter can leave the old image section mapped briefly.
        # Archive the exact old file and install a new file, only after game exit.
        $old = Join-Path $backup ('replaced/' + $relative)
        New-Item -ItemType Directory -Force (Split-Path -Parent $old) | Out-Null
        Move-Item -LiteralPath $target -Destination $old
    }
    Copy-Item -LiteralPath $_.FullName -Destination $target
    if ((Get-FileHash -LiteralPath $_.FullName).Hash -ne (Get-FileHash -LiteralPath $target).Hash) { throw "Installation mismatch: $target" }
}
Write-Output "Installed and verified BetterExpedition: $destination"
