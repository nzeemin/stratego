@echo off
rem Build stratego.sav with the UKNC PDP-11 GCC toolchain (needs GNU make on PATH).
rem Override the toolchain location with UKNC before running.
if "%UKNC%"=="" set "UKNC=%LOCALAPPDATA%\Programs\UKNC"
set "PATH=%UKNC%\gcc\bin;%PATH%"

make UKNC=%UKNC:\=/%
if errorlevel 1 goto Failed
dir /-c build\STRATE.SAV|findstr /R /C:"STRATE.SAV"
echo SUCCESS
exit /b 0

:Failed
echo FAILED
exit /b 1
