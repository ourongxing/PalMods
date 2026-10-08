@echo off
setlocal
if not defined PALCOMBO_BUILD set "PALCOMBO_BUILD=%~dp0../../../.build/PalCombo"
if not defined UE4SS_BUILD set "UE4SS_BUILD=%~dp0../../../.build/UE4SS"
cmake -S "%~dp0../native" -B "%PALCOMBO_BUILD%" -G "Visual Studio 17 2022" "-DPalModsSDK_DIR=%UE4SS_BUILD%" %*
exit /b %errorlevel%
