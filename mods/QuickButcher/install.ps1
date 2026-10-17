param([string]$GameRoot)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../tools/paths.ps1')
if (-not $GameRoot) {
    $binaries = Split-Path -Parent (Get-PalModsGamePaths).GameExecutable
    $GameRoot = [IO.Path]::GetFullPath((Join-Path $binaries '../../..'))
}
if (Get-Process -Name 'Palworld-Win64-Shipping' -ErrorAction SilentlyContinue) {
    throw 'Close Palworld before installing QuickButcher.'
}
$repository = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$output = Join-Path $repository 'dist/QuickButcher'
$source = Join-Path $output 'QuickButcher_P.pak'
$audit = Get-Content -LiteralPath (Join-Path $output 'build-audit.json') -Raw | ConvertFrom-Json
if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $audit.PakSHA256) {
    throw 'PAK differs from the verified build; rebuild first.'
}
if (-not (Test-Path -LiteralPath (Join-Path $GameRoot 'Pal/Content/Paks/Pal-Windows.pak'))) {
    throw 'Palworld game directory not found.'
}
$target = Join-Path $GameRoot 'Pal/Content/Paks/~mods/QuickButcher/QuickButcher_P.pak'
if (Test-Path -LiteralPath $target) {
    $backup = Join-Path $repository ('.build/QuickButcher/backups/' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    Copy-Item -LiteralPath $target -Destination $backup
    if ((Get-FileHash -LiteralPath $target).Hash -ne (Get-FileHash -LiteralPath (Join-Path $backup 'QuickButcher_P.pak')).Hash) {
        throw 'Backup verification failed.'
    }
    Write-Output "Backup: $backup"
}
New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
Copy-Item -LiteralPath $source -Destination $target -Force
if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -ne $audit.PakSHA256) {
    throw 'Installed PAK hash mismatch.'
}
Write-Output "Installed QuickButcher: $target"
Write-Output 'Restart Palworld. In-game verification is still required.'
