param([string]$GameRoot = 'G:/SteamLibrary/steamapps/common/Palworld')
$ErrorActionPreference = 'Stop'
if (Get-Process 'Palworld','Palworld-Win64-Shipping','PalServer-Win64-Shipping' -ErrorAction SilentlyContinue) {
    throw 'Close Palworld before installing BetterExpedition.'
}
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$source = Join-Path $root 'dist/BetterExpedition/BetterExpedition'
$ue4ss = Join-Path $GameRoot 'Mods/NativeMods/UE4SS/Mods'
$destination = Join-Path $ue4ss 'PalSchema/mods/BetterExpedition'
if (-not (Test-Path (Join-Path $source 'raw/expedition_time.json'))) { throw 'Build BetterExpedition first.' }
if (-not (Test-Path (Join-Path $ue4ss 'PalSchema/dlls/main.dll'))) { throw 'Local PalSchema not found.' }
$backup = Join-Path $root ('.build/BetterExpedition/time-only-install-backups/' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
# Archive the exact old mod roots, so obsolete executable files cannot remain active.
foreach ($old in @((Join-Path $ue4ss 'BetterExpedition'), $destination)) {
    $resolved = [IO.Path]::GetFullPath($old)
    if (-not $resolved.StartsWith([IO.Path]::GetFullPath($ue4ss) + [IO.Path]::DirectorySeparatorChar)) { throw 'Unsafe install path.' }
    if (Test-Path -LiteralPath $old) {
        $label = if ($old -eq $destination) { 'PalSchema' } else { 'UE4SS' }
        New-Item -ItemType Directory -Force $backup | Out-Null
        Move-Item -LiteralPath $old -Destination (Join-Path $backup $label)
    }
}
New-Item -ItemType Directory -Force $destination | Out-Null
Copy-Item -Path (Join-Path $source '*') -Destination $destination -Recurse
Get-ChildItem -LiteralPath $source -File -Recurse | ForEach-Object {
    $target = Join-Path $destination $_.FullName.Substring($source.Length + 1)
    if ((Get-FileHash -LiteralPath $_.FullName).Hash -ne (Get-FileHash -LiteralPath $target).Hash) { throw "Installation mismatch: $target" }
}
Write-Output "Installed and verified time-only BetterExpedition: $destination"
