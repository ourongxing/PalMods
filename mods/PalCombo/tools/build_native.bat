@echo off
setlocal
if not defined PALCOMBO_BUILD set "PALCOMBO_BUILD=%~dp0../../../.build/PalCombo"
call "%~dp0configure_native.bat" %*
if errorlevel 1 exit /b %errorlevel%
cmake --build "%PALCOMBO_BUILD%" --config Game__Shipping__Win64
