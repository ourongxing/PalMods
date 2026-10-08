@echo off
call "%~dp0configure_native.bat" %*
if errorlevel 1 exit /b %errorlevel%
cmake --build "%~dp0../../../.build/PalCombo" --config Game__Shipping__Win64
