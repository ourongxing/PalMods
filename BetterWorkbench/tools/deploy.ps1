param(
    [string]$ModsDirectory = '',
    [string]$GameExecutable = ''
)
$ErrorActionPreference = 'Stop'
# Both entry points deploy the same combined Lua/native mod.
& (Join-Path $PSScriptRoot 'deploy_native.ps1') -ModsDirectory $ModsDirectory -GameExecutable $GameExecutable
