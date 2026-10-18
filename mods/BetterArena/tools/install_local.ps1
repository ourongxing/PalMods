param([string]$GameRoot = 'G:/SteamLibrary/steamapps/common/Palworld')
$ErrorActionPreference = 'Stop'
if (Get-Process 'Palworld-Win64-Shipping' -ErrorAction SilentlyContinue) {
    throw 'Close Palworld before installing BetterArena.'
}
$source = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../mod'))
$destination = Join-Path $GameRoot 'Mods/NativeMods/UE4SS/Mods/BetterArena'
if (-not (Test-Path (Join-Path $GameRoot 'Mods/NativeMods/UE4SS/UE4SS.dll'))) {
    throw 'The local UE4SS installation was not found.'
}
New-Item -ItemType Directory -Path $destination -Force | Out-Null
Copy-Item -Path "$source/*" -Destination $destination -Recurse -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../README.md') -Destination $destination -Force
New-Item -ItemType Directory -Path (Join-Path $env:LOCALAPPDATA 'Pal/Saved/BetterArena') -Force | Out-Null
Write-Output "Installed BetterArena to $destination"
