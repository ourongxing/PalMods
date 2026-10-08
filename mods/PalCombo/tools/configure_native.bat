@echo off
cmake -S "%~dp0../native" -B "%~dp0../../../.build/PalCombo" -G "Visual Studio 17 2022" %*
