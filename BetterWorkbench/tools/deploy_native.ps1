param(
    [string]$ModsDirectory = '',
    [string]$GameExecutable = '',
    [switch]$StageWhileRunning
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../tools/paths.ps1')
$gamePaths = Get-PalModsGamePaths
if (-not $ModsDirectory) { $ModsDirectory = $gamePaths.ModsDirectory }
if (-not $GameExecutable) { $GameExecutable = $gamePaths.GameExecutable }
$projectRoot = Split-Path -Parent $PSScriptRoot
$buildRoot = Join-Path $projectRoot '.tools\native-candidate'
$sourceDll = Join-Path $buildRoot 'build\Release\BetterWorkbenchNative.dll'
$report = Get-Content -LiteralPath (Join-Path $buildRoot 'import-audit.json') -Raw | ConvertFrom-Json
$runtimeDll = Join-Path (Split-Path -Parent $ModsDirectory) 'UE4SS.dll'
if ((Get-FileHash -LiteralPath $sourceDll).Hash -ne $report.bridge_sha256) { throw 'Bridge differs from audited build' }
if ((Get-FileHash -LiteralPath $runtimeDll).Hash -ne $report.runtime_sha256) { throw 'UE4SS changed since import audit' }
if ((Get-FileHash -LiteralPath $GameExecutable).Hash -ne (Get-Content -LiteralPath (Join-Path $buildRoot 'game-sha256.txt') -Raw).Trim()) { throw 'Game executable changed since native guard generation' }
$running = [bool](Get-Process -Name 'Palworld-Win64-Shipping' -ErrorAction SilentlyContinue)
if ($running) { throw 'Save and exit Palworld before deploying the unified mod, including staging' }
$modsRoot = [IO.Path]::GetFullPath($ModsDirectory).TrimEnd([char[]]'\/')
$targetDir = Join-Path $modsRoot 'BetterWorkbench'
$legacyDirs = @('SmartRecipe', 'SmartRecipeNative', 'BetterWorkbenchNative') | ForEach-Object { Join-Path $modsRoot $_ }
foreach ($directory in @($targetDir) + $legacyDirs) {
    if ([IO.Path]::GetDirectoryName($directory) -ne $modsRoot) { throw 'Mod directory is outside the selected Mods directory' }
}
$targetJobs = Join-Path $targetDir 'Jobs'
$jobFiles = @()
$jobHashes = @{}
foreach ($legacyDir in $legacyDirs) {
    $legacyJobs = Join-Path $legacyDir 'Jobs'
    if (-not (Test-Path -LiteralPath $legacyJobs)) { continue }
    foreach ($file in (Get-ChildItem -LiteralPath $legacyJobs -Recurse -File)) {
        $relative = $file.FullName.Substring($legacyJobs.Length + 1)
        $destination = Join-Path $targetJobs $relative
        $hash = (Get-FileHash -LiteralPath $file.FullName).Hash
        if ($jobHashes.ContainsKey($relative) -and $jobHashes[$relative] -ne $hash) { throw "Conflicting legacy job definition: $relative" }
        if ((Test-Path -LiteralPath $destination) -and (Get-FileHash -LiteralPath $destination).Hash -ne $hash) { throw "Conflicting job definition: $relative" }
        $jobHashes[$relative] = $hash
        $jobFiles += [pscustomobject]@{ Source = $file.FullName; Relative = $relative; Hash = $hash }
    }
}
$modsFile = Join-Path $ModsDirectory 'mods.txt'
$backupDir = Join-Path $projectRoot ('.tools\deployment-backups\unified-' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
Copy-Item -LiteralPath $modsFile -Destination (Join-Path $backupDir 'mods.txt')
foreach ($directory in @($targetDir) + $legacyDirs) {
    if (Test-Path -LiteralPath $directory) { Copy-Item -LiteralPath $directory -Destination $backupDir -Recurse }
}
$sourceDir = Join-Path $projectRoot 'Mods\BetterWorkbench'
Copy-Item -LiteralPath $sourceDir -Destination $modsRoot -Recurse -Force
$dllDir = Join-Path $targetDir 'dlls'
New-Item -ItemType Directory -Path $dllDir -Force | Out-Null
$installedDll = Join-Path $dllDir 'main.dll'
Copy-Item -LiteralPath $sourceDll -Destination $installedDll -Force
Copy-Item -LiteralPath (Join-Path $buildRoot 'import-audit.json') -Destination (Join-Path $targetDir 'import-audit.json') -Force
Copy-Item -LiteralPath (Join-Path $projectRoot 'Native\README.md') -Destination (Join-Path $targetDir 'README.md') -Force
if ((Get-FileHash -LiteralPath $installedDll).Hash -ne $report.bridge_sha256) { throw 'Installed DLL hash mismatch' }
foreach ($file in (Get-ChildItem -LiteralPath $sourceDir -Recurse -File)) {
    $relative = $file.FullName.Substring($sourceDir.Length + 1)
    if ((Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath (Join-Path $targetDir $relative)).Hash) { throw "Lua deployment mismatch: $relative" }
}
foreach ($file in $jobFiles) {
    $relative = $file.Relative
    $destination = Join-Path $targetJobs $relative
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $file.Source -Destination $destination -Force
    if ((Get-FileHash -LiteralPath $destination).Hash -ne $file.Hash) { throw "Job migration mismatch: $relative" }
}
# Remove the legacy DLL from discovery, retaining the entire folder in backup.
foreach ($legacyDir in $legacyDirs) {
    if (Test-Path -LiteralPath $legacyDir) { Move-Item -LiteralPath $legacyDir -Destination (Join-Path $backupDir ('retired-' + (Split-Path -Leaf $legacyDir))) }
}
$contents = [IO.File]::ReadAllText($modsFile)
$contents = [regex]::Replace($contents, '(?m)^[ \t]*(?:SmartRecipe|BetterWorkbench)(?:Native)?[ \t]*:[^\r\n]*\r?\n?', '')
$marker = '; Built-in keybinds, do not move up!'
if ($contents.Contains($marker)) {
    $contents = $contents.Replace($marker, "BetterWorkbench : 1`r`n" + $marker)
} else {
    $contents = $contents.TrimEnd([char[]]"`r`n") + "`r`nBetterWorkbench : 1`r`n"
}
[IO.File]::WriteAllText($modsFile, $contents, [Text.UTF8Encoding]::new($false))
Write-Output "Deployed unified BetterWorkbench: $targetDir; migrated Jobs: $($jobFiles.Count)"
Write-Output "SHA256: $($report.bridge_sha256)"
Write-Output "Backup: $backupDir"
Write-Output 'Restart Palworld; verify C++ and Lua BetterWorkbench startup and ACTIVE_CRAFTING enabled.'
