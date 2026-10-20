param(
    [string]$GameRoot = 'G:/SteamLibrary/steamapps/common/Palworld',
    [string]$WorkshopRoot = 'G:/SteamLibrary/steamapps/workshop/content/1623730/3820049820'
)
$ErrorActionPreference = 'Stop'
if (Get-Process -Name Palworld,Palworld-Win64-Shipping -ErrorAction SilentlyContinue) {
    throw 'Exit Palworld before installing BetterStorage.'
}
$repo = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
$source = Join-Path $repo 'mods/BetterStorage/mod/Scripts/main.lua'
$runtime = Join-Path $GameRoot 'Mods/NativeMods/UE4SS/Mods/BetterStorage/Scripts/main.lua'
$workshop = Join-Path $WorkshopRoot 'Scripts/main.lua'
$infoPath = Join-Path $WorkshopRoot 'Info.json'
$backup = Join-Path $repo ('.build/BetterStorage/client-install/' + [guid]::NewGuid().ToString('N'))
foreach ($path in @($source,$runtime,$workshop,$infoPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing file: $path" }
}
New-Item -ItemType Directory -Path $backup | Out-Null
Copy-Item -LiteralPath $runtime -Destination (Join-Path $backup 'runtime-main.lua')
Copy-Item -LiteralPath $workshop -Destination (Join-Path $backup 'workshop-main.lua')
Copy-Item -LiteralPath $infoPath -Destination (Join-Path $backup 'Info.json')
$info = Get-Content -LiteralPath $infoPath -Raw | ConvertFrom-Json
if ($info.PackageName -ne 'BetterStorage') { throw 'Wrong Workshop package.' }
$info.DebugMode = $true
$info | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $infoPath -Encoding utf8NoBOM
Copy-Item -LiteralPath $source -Destination $workshop -Force
Copy-Item -LiteralPath $source -Destination $runtime -Force
$hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
foreach ($path in @($runtime,$workshop)) {
    if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $hash) { throw 'Installed hash mismatch.' }
}
Write-Output "Backup: $backup"
Write-Output "Client Lua SHA256: $hash"
