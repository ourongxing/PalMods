param([string]$OutputDirectory = '')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $projectRoot 'dist\better-workbench-0.6.2-unified' }
$packageRoot = [IO.Path]::GetFullPath($OutputDirectory)
$buildRoot = Join-Path $projectRoot '.tools\native-candidate'
$validation = Get-Content -LiteralPath (Join-Path $buildRoot 'validation.json') -Raw | ConvertFrom-Json
foreach ($entry in $validation.sources) {
    if ((Get-FileHash -LiteralPath (Join-Path $projectRoot $entry.path)).Hash -ne $entry.sha256) { throw "Validation record is stale: $($entry.path)" }
}
$reportPath = Join-Path $buildRoot 'import-audit.json'
$report = Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
$sourceDll = Join-Path $buildRoot 'build\Release\BetterWorkbenchNative.dll'
if ((Get-FileHash -LiteralPath $sourceDll).Hash -ne $report.bridge_sha256) { throw 'DLL differs from audited candidate' }
if ($validation.native_sha256 -ne $report.bridge_sha256) { throw 'DLL differs from tested candidate' }
if ($report.ue4ss_imports_verified -lt 46) { throw 'Snapshot candidate imports have not been audited' }
if (Test-Path -LiteralPath $packageRoot) { throw "Package already exists; use a fresh directory: $packageRoot" }
$modsRoot = Join-Path $packageRoot 'Mods'
New-Item -ItemType Directory -Path $modsRoot -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'Mods\BetterWorkbench') -Destination $modsRoot -Recurse
$nativeRoot = Join-Path $modsRoot 'BetterWorkbench'
$nativeDllRoot = Join-Path $nativeRoot 'dlls'
New-Item -ItemType Directory -Path $nativeDllRoot -Force | Out-Null
Copy-Item -LiteralPath $sourceDll -Destination (Join-Path $nativeDllRoot 'main.dll')
Copy-Item -LiteralPath $reportPath -Destination (Join-Path $nativeRoot 'import-audit.json')
Copy-Item -LiteralPath (Join-Path $projectRoot 'Native\README.md') -Destination (Join-Path $nativeRoot 'README.md')
Copy-Item -LiteralPath (Join-Path $projectRoot 'README.md') -Destination (Join-Path $packageRoot 'README.md')
[IO.File]::WriteAllText((Join-Path $packageRoot 'mods-to-enable.txt'), "BetterWorkbench : 1`r`n", [Text.UTF8Encoding]::new($false))
$entries = @(Get-ChildItem -LiteralPath $packageRoot -Recurse -File | ForEach-Object {
    [ordered]@{ path = $_.FullName.Substring($packageRoot.Length + 1).Replace('\', '/'); sha256 = (Get-FileHash -LiteralPath $_.FullName).Hash }
})
$manifest = [ordered]@{
    name = 'better workbench'; name_zh = '更好的工作台'
    schema = 1; version = '0.6.2-native-debits'; mode = 'current-workbench-native-crafting'; live_crafting_verified = $false
    runtime_sha256 = $report.runtime_sha256; native_sha256 = $report.bridge_sha256
    ue4ss_imports_verified = $report.ue4ss_imports_verified
    game_sha256 = (Get-Content -LiteralPath (Join-Path $buildRoot 'game-sha256.txt') -Raw).Trim()
    lua_tests_passed = $validation.lua_tests_passed; cooked_recipes_validated = $validation.cooked_recipes_validated
    native_view_tests_passed = $validation.native_view_tests_passed
    crafting_writes_enabled = $true; native_save_integration_enabled = $true; files = $entries
    supported_root_scope = 'all native GetRecipes entries at the current workbench'; maximum_expanded_batches = 256
    maximum_actual_input_types = 64; native_performance_caches_enabled = $false
    lua_background_diagnostics_enabled = $false; unified_mod_directory = 'BetterWorkbench'
    storage_capacity_probe_enabled = $true; storage_capacity_writes_enabled = $true
    native_output_slot = 5; dynamic_input_mapping = '0..4,6..64'; unsupported_containers_maximum_input_types = 5
    full_native_transaction_debits_enabled = $true; completion_slot_preflight_enabled = $true; bounded_actual_debit_audit_enabled = $true
    vanilla_material_scroll_enabled = $true; material_scroll_visible_rows = 5
    ui_expanded_material_display = $true; intermediate_extra_work_enabled = $false
}
[IO.File]::WriteAllText((Join-Path $packageRoot 'manifest.json'), ($manifest | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
Write-Output "Packaged audited current-workbench native crafting candidate: $packageRoot"
Write-Output "Verified file inventory: $($entries.Count) entries; game deployment not performed."
