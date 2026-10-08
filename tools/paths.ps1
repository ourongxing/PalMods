function Get-PalModsGamePaths {
    $gameRoot = if ($env:PALWORLD_ROOT) { $env:PALWORLD_ROOT } else { 'G:\SteamLibrary\steamapps\common\Palworld' }
    @{
        ModsDirectory = Join-Path $gameRoot 'Mods/NativeMods/UE4SS/Mods'
        GameExecutable = Join-Path $gameRoot 'Pal/Binaries/Win64/Palworld-Win64-Shipping.exe'
    }
}
