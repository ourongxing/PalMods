param([string]$GameRoot = 'G:/SteamLibrary/steamapps/common/Palworld')
$ErrorActionPreference = 'Stop'
if (Get-Process 'Palworld','Palworld-Win64-Shipping','PalServer-Win64-Shipping' -ErrorAction SilentlyContinue) {
    throw 'Close Palworld before installing SekhmetMedicine.'
}
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$source = Join-Path $root 'dist/SekhmetMedicine/SekhmetMedicine'
$schema = Join-Path $GameRoot 'Mods/NativeMods/UE4SS/Mods/PalSchema'
$destination = Join-Path $schema 'mods/SekhmetMedicine'
if (-not (Test-Path (Join-Path $source 'raw/sekhmet_medicine.json'))) { throw 'Build first.' }
if (-not (Test-Path (Join-Path $schema 'dlls/main.dll'))) { throw 'Local PalSchema not found.' }
if (Test-Path $destination) {
    $backup = Join-Path $root ('.build/SekhmetMedicine/backups/' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
    New-Item -ItemType Directory -Force $backup | Out-Null
    Copy-Item -LiteralPath $destination -Destination $backup -Recurse
}
New-Item -ItemType Directory -Force $destination | Out-Null
Copy-Item -Path (Join-Path $source '*') -Destination $destination -Recurse -Force
Get-ChildItem -LiteralPath $source -File -Recurse | ForEach-Object {
    $target = Join-Path $destination $_.FullName.Substring($source.Length + 1)
    if ((Get-FileHash -LiteralPath $_.FullName).Hash -ne (Get-FileHash -LiteralPath $target).Hash) { throw "Mismatch: $target" }
}
Write-Output "Installed and verified: $destination"
