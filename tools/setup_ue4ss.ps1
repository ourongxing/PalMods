param(
    [string]$DependencyDirectory = (Join-Path $PSScriptRoot '../.tools/RE-UE4SS')
)
$ErrorActionPreference = 'Stop'
$revision = '2281fa311e417b1dfddedbcd49972d764fddb244'
if (Test-Path -LiteralPath $DependencyDirectory) {
    if (-not (Test-Path -LiteralPath (Join-Path $DependencyDirectory '.git'))) {
        throw 'Existing UE4SS directory is a source snapshot without Git metadata. Keep it for cached builds; use -DependencyDirectory with a new empty path for a pinned clone. Do not delete the snapshot before preserving its Unreal dependency.'
    }
    $actual = git -C $DependencyDirectory rev-parse HEAD
    if ($LASTEXITCODE -ne 0 -or $actual -ne $revision) { throw 'Existing UE4SS checkout does not match pinned revision' }
} else {
    git clone https://github.com/UE4SS-RE/RE-UE4SS.git $DependencyDirectory
    if ($LASTEXITCODE -ne 0) { throw 'Could not clone RE-UE4SS' }
    git -C $DependencyDirectory checkout $revision
    if ($LASTEXITCODE -ne 0) { throw 'Could not check out pinned RE-UE4SS revision' }
}
git -C $DependencyDirectory submodule update --init --recursive
if ($LASTEXITCODE -ne 0) { throw 'Could not initialize RE-UE4SS submodules' }
