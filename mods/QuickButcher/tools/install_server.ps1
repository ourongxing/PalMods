param([string]$ServerRoot = 'G:\PalworldTestServer')
$ErrorActionPreference = 'Stop'
if (Get-Process -Name 'Palworld-Win64-Shipping','PalServer-Win64-Shipping-Cmd','PalServer-Win64-Shipping','PalServer' -ErrorAction SilentlyContinue) {
    throw 'Close Palworld and stop the dedicated server before installing QuickButcher.'
}
$repository = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$ServerRoot = [IO.Path]::GetFullPath($ServerRoot)
if (-not (Test-Path -LiteralPath (Join-Path $ServerRoot 'Pal/Content/Paks/Pal-WindowsServer.pak'))) {
    throw 'Dedicated server directory not found.'
}
$output = Join-Path $repository 'dist/QuickButcher/server'
$source = Join-Path $output 'QuickButcher_P.pak'
$audit = Get-Content -LiteralPath (Join-Path $output 'build-audit.json') -Raw | ConvertFrom-Json
if ($audit.Target -ne 'server' -or (Get-FileHash -LiteralPath $source).Hash.ToLowerInvariant() -ne $audit.PakSHA256) {
    throw 'Server build audit does not match the PAK.'
}
$package = Join-Path $ServerRoot 'Mods/Workshop/3821569615'
$infoPath = Join-Path $package 'Info.json'
$info = Get-Content -LiteralPath $infoPath -Raw | ConvertFrom-Json
if ($info.PackageName -ne 'QuickButcher') { throw 'Unexpected Workshop package.' }
$settingsPath = Join-Path $ServerRoot 'Mods/PalModSettings.ini'
$settings = [IO.File]::ReadAllText($settingsPath)
if ($settings -notmatch '(?im)^bGlobalEnableMod=True\s*$') { throw 'Server mod loader is not enabled.' }
$backup = Join-Path $repository ('.build/QuickButcher/server-install/' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
Copy-Item -LiteralPath $package -Destination (Join-Path $backup 'package') -Recurse
Copy-Item -LiteralPath $settingsPath -Destination $backup
Copy-Item -LiteralPath (Join-Path $ServerRoot 'Pal/Saved') -Destination (Join-Path $backup 'Saved') -Recurse
$targetDirectory = Join-Path $package 'Server/Paks'
New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
$target = Join-Path $targetDirectory 'QuickButcher_P.pak'
Copy-Item -LiteralPath $source -Destination $target -Force
if ((Get-FileHash -LiteralPath $target).Hash.ToLowerInvariant() -ne $audit.PakSHA256) { throw 'Copied server PAK hash mismatch.' }
$rules = @($info.InstallRule | Where-Object {-not $_.IsServer})
$rules += [pscustomobject]@{Type='Paks';IsServer=$true;Targets=@('./Server/Paks/')}
$info.InstallRule = $rules
$info.Version = $audit.Version
[IO.File]::WriteAllText($infoPath,($info | ConvertTo-Json -Depth 10),[Text.UTF8Encoding]::new($false))
if ($settings -notmatch '(?m)^ActiveModList=QuickButcher\r?$') { $settings += "`r`nActiveModList=QuickButcher`r`n" }
[IO.File]::WriteAllText($settingsPath,$settings,[Text.UTF8Encoding]::new($false))
Write-Output "Server package staged: $target"
Write-Output "Backup: $backup"
Write-Output 'Restart the server to deploy. Actual butcher behavior still requires in-game verification.'
