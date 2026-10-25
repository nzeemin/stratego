@echo off
REM ===========================================================================
REM  Build the Stratego game core (C, via z88dk / sccz80) as a position-fixed
REM  blob that strateg1.asm links against by address.
REM
REM  Outputs (in core\):
REM    core.bin  - raw machine code + data, ORG = CORE_ORG, load as-is
REM    core.map  - z80asm link map
REM    core.inc  - sjasmplus include: CORE_ORG / CORE_END / CORE_SIZE,
REM                entry-point EQUs, g_state address, GS_* struct offsets
REM
REM  Integration: strateg1.asm does  INCLUDE "core\core.inc"  then
REM               calls e.g.  call ai_choose_move  (sccz80: args pushed
REM               left->right, caller cleans, result in HL/L).
REM               !compile.cmd places core.bin into the ROM image at CORE_ORG.
REM ===========================================================================
setlocal enabledelayedexpansion

if "%Z88DK%"=="" set Z88DK=C:\bin\z88dk
set ZCCCFG=%Z88DK%\lib\config
set PATH=%Z88DK%\bin;%PATH%

set CORE=core
set SRC=state.c rng.c game.c ai.c
set OUT=core

pushd "%~dp0%CORE%"

if exist %OUT%.bin del %OUT%.bin
if exist %OUT%.map del %OUT%.map
if exist %OUT%.inc del %OUT%.inc
del *.o 2>nul

echo Compiling + linking game core...
zcc +vector06c -m8080 -SO2 -O2 -crt0=core_crt0 -o %OUT%.bin -m %SRC%
if errorlevel 1 goto :fail
if not exist %OUT%.bin goto :fail
if not exist %OUT%.map goto :fail

echo Generating %OUT%.inc ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0%CORE%\map2inc.ps1" -Map "%OUT%.map" -Out "%OUT%.inc"
if errorlevel 1 goto :fail

for %%I in (%OUT%.bin) do set /a BINSZ=%%~zI
echo.
echo   core.bin  %BINSZ% bytes
type %OUT%.inc | findstr /R /C:"CORE_ORG" /C:"CORE_END" /C:"CORE_SIZE" /C:"CORE_FREE"
echo   (CORE_FREE = bytes up to the screen at 0A000h)
echo.
echo Core build OK.
popd
endlocal
goto :eof

:fail
echo.
echo CORE BUILD FAILED
popd
endlocal
exit /b 1
