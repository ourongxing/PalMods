@echo off
cmake -S "%~dp0" -B "%~dp0build" -G "Visual Studio 17 2022"
if errorlevel 1 exit /b %errorlevel%
cmake --build "%~dp0build" --config Game__Shipping__Win64
