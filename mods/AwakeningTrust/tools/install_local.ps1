param([string]$GameRoot = '', [switch]$Server)
if (-not $GameRoot) { $GameRoot = if ($Server) { 'G:/PalworldTestServer' } else { 'G:/SteamLibrary/steamapps/common/Palworld' } }
$ErrorActionPreference = 'Stop'
if (Get-Process 'Palworld','Palworld-Win64-Shipping','PalServer-Win64-Shipping','PalServer-Win64-Shipping-Cmd' -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith([IO.Path]::GetFullPath($GameRoot) + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) }) {
    throw 'Close Palworld before installing AwakeningTrust.'
}
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$source = Join-Path $root $(if ($Server) { 'dist/AwakeningTrust/server/AwakeningTrust-0.3.0' } else { 'dist/AwakeningTrust/AwakeningTrust-0.3.0' })
$mods = [IO.Path]::GetFullPath((Join-Path $GameRoot 'Mods/NativeMods/UE4SS/Mods'))
$destination = Join-Path $mods 'AwakeningTrust'
$backup = Join-Path $root ('.build/AwakeningTrust/backups/' + $(if ($Server) { 'server-' } else { 'client-' }) + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
if (-not (Test-Path (Join-Path $source 'dlls/main.dll'))) { throw 'Build first.' }
if (-not (Test-Path (Join-Path $mods '../UE4SS.dll'))) { throw 'Local UE4SS not found.' }
$exe = Join-Path $GameRoot $(if ($Server) { 'Pal/Binaries/Win64/PalServer-Win64-Shipping-Cmd.exe' } else { 'Pal/Binaries/Win64/Palworld-Win64-Shipping.exe' })
$expected = if ($Server) { '6f929673e7ac637d591d6f3454dbd396be7911093311cb8b24af3a152b217f49' } else { 'e590b5e7bfaa3fea40fab1a02cc72c8fc5fd6f8631ef2308e95ac56c25195837' }
if ((Get-FileHash -LiteralPath $exe).Hash -ne $expected) { throw 'Unsupported deployment binary.' }
New-Item -ItemType Directory -Force $backup | Out-Null
# Back up only this installation, after checking its absolute destination.
$resolved = [IO.Path]::GetFullPath($destination)
if (-not $resolved.StartsWith($mods + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Destination escapes Mods root.' }
if (Test-Path -LiteralPath $resolved) {
    Move-Item -LiteralPath $resolved -Destination (Join-Path $backup 'native')
}
New-Item -ItemType Directory -Force $destination | Out-Null
Copy-Item -Path (Join-Path $source '*') -Destination $destination -Recurse -Force
Get-ChildItem -LiteralPath $source -File -Recurse | ForEach-Object {
    $target = Join-Path $destination $_.FullName.Substring($source.Length + 1)
    if ((Get-FileHash -LiteralPath $_.FullName).Hash -ne (Get-FileHash -LiteralPath $target).Hash) { throw "Mismatch: $target" }
}
Write-Output "Installed and verified: $destination"
$list = Join-Path $mods 'mods.txt'
if (Test-Path -LiteralPath $list) {
    Copy-Item -LiteralPath $list -Destination (Join-Path $backup 'mods.txt')
    $text = Get-Content -LiteralPath $list -Raw
    if ($text -match '(?m)^AwakeningTrust\s*:') { $text = $text -replace '(?m)^AwakeningTrust\s*:\s*\d+','AwakeningTrust : 1' }
    else { $text += "`r`nAwakeningTrust : 1`r`n" }
    Set-Content -LiteralPath $list -Value $text -Encoding utf8
}
