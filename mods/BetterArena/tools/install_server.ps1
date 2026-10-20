param([string]$ServerRoot = 'G:/PalworldTestServer')
$ErrorActionPreference = 'Stop'
if (Get-Process -Name 'Palworld-Win64-Shipping','Palworld','PalServer-Win64-Shipping-Cmd','PalServer-Win64-Shipping','PalServer' -ErrorAction SilentlyContinue) {
    throw 'Close Palworld and stop the server before installing BetterArena.'
}
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$mods = Join-Path $ServerRoot 'Mods/NativeMods/UE4SS/Mods'
if (-not (Test-Path -LiteralPath (Join-Path $mods 'PalSchema/dlls/main.dll'))) { throw 'Server PalSchema not found.' }
$target = Join-Path $mods 'BetterArena'
$backup = Join-Path $repo ('.build/BetterArena/server-install/' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
if (Test-Path -LiteralPath $target) { Copy-Item -LiteralPath $target -Destination (Join-Path $backup 'BetterArena') -Recurse }
Copy-Item -LiteralPath (Join-Path $ServerRoot 'Pal/Saved') -Destination (Join-Path $backup 'Saved') -Recurse
$control = Join-Path $mods 'mods.txt'
Copy-Item -LiteralPath $control -Destination $backup
& (Join-Path $PSScriptRoot 'install_local.ps1') -GameRoot $ServerRoot
[IO.File]::WriteAllText((Join-Path $target 'server.txt'),'Dedicated server', [Text.UTF8Encoding]::new($false))
New-Item -ItemType Directory -Path (Join-Path $ServerRoot 'Pal/Saved/BetterArena') -Force | Out-Null
$text = [IO.File]::ReadAllText($control)
$text = [regex]::Replace($text,'(?m)^[ \t]*BetterArena[ \t]*:[ \t]*[01][ \t]*(?:\r?\n|$)','')
[IO.File]::WriteAllText($control,$text.TrimEnd()+"`r`nBetterArena : 1`r`n",[Text.UTF8Encoding]::new($false))
Write-Output "Installed server BetterArena. Backup: $backup"
