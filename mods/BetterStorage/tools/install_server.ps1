param([string]$ServerRoot = 'G:\PalworldTestServer')
$ErrorActionPreference = 'Stop'
if (Get-Process -Name 'Palworld-Win64-Shipping','PalServer-Win64-Shipping-Cmd','PalServer-Win64-Shipping','PalServer' -ErrorAction SilentlyContinue) {
    throw 'Close Palworld and stop the server before installing.'
}
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$mods = Join-Path $ServerRoot 'Mods/NativeMods/UE4SS/Mods'
if (-not (Test-Path -LiteralPath (Join-Path $mods 'mods.txt'))) { throw 'Server UE4SS installation not found.' }
$stage = Join-Path $repo 'dist/BetterStorage/server/BetterStorage'
$audit = Get-Content -LiteralPath (Join-Path $repo '.build/BetterStorage/server-native/import-audit.json') -Raw | ConvertFrom-Json
$dll = Join-Path $stage 'dlls/main.dll'
if ($audit.target -ne 'server' -or (Get-FileHash -LiteralPath $dll).Hash.ToLowerInvariant() -ne $audit.dll_sha256) { throw 'Server build audit mismatch.' }
$backup = Join-Path $repo ('.build/BetterStorage/server-install/' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
$target = Join-Path $mods 'BetterStorage'
if (Test-Path -LiteralPath $target) { Copy-Item -LiteralPath $target -Destination (Join-Path $backup 'BetterStorage') -Recurse }
Copy-Item -LiteralPath (Join-Path $mods 'mods.txt') -Destination $backup
Copy-Item -LiteralPath (Join-Path $ServerRoot 'Pal/Saved') -Destination (Join-Path $backup 'Saved') -Recurse
New-Item -ItemType Directory -Path (Join-Path $target 'dlls') -Force | Out-Null
Copy-Item -LiteralPath $dll -Destination (Join-Path $target 'dlls/main.dll') -Force
Copy-Item -LiteralPath (Join-Path $stage 'enabled.txt') -Destination (Join-Path $target 'enabled.txt') -Force
$control = Join-Path $mods 'mods.txt'
$text = [IO.File]::ReadAllText($control)
$text = [regex]::Replace($text,'(?m)^[ \t]*BetterStorage[ \t]*:[ \t]*[01][ \t]*(?:\r?\n|$)','')
$text = [regex]::Replace($text,'(?m)^[ \t]*Keybinds[ \t]*:[ \t]*[01][ \t]*(?:\r?\n|$)','')
[IO.File]::WriteAllText($control,$text.TrimEnd()+"`r`nBetterStorage : 1`r`nKeybinds : 1`r`n",[Text.UTF8Encoding]::new($false))
if ((Get-FileHash -LiteralPath (Join-Path $target 'dlls/main.dll')).Hash.ToLowerInvariant() -ne $audit.dll_sha256) {throw 'Installed DLL hash mismatch'}
Write-Output "Installed server DLL. Existing PalSchema configuration preserved. Backup: $backup"
