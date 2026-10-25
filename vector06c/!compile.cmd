@echo off
if exist strateg0.bin del strateg0.bin
if exist strateg0.inc del strateg0.inc
if exist stratego.bin del stratego.bin
if exist stratego.txt del stratego.txt
if exist stratego.zx0 del stratego.zx0
if exist stratego.rom del stratego.rom

rem Define ESCchar to use in ANSI escape sequences
rem https://stackoverflow.com/questions/2048509/how-to-echo-with-different-colors-in-the-windows-command-line
for /F "delims=#" %%E in ('"prompt #$E# & for %%E in (1) do rem"') do set "ESCchar=%%E"

for /f "tokens=2 delims==" %%a in ('wmic OS Get localdatetime /value') do set "dt=%%a"
set "YY=%dt:~2,2%" & set "YYYY=%dt:~0,4%" & set "MM=%dt:~4,2%" & set "DD=%dt:~6,2%"
set "DATESTAMP=%YYYY%-%MM%-%DD%"
for /f %%i in ('git rev-list HEAD --count') do (set REVISION=%%i)
echo VER.%REVISION% %DATESTAMP%
echo 	DEFM "VER.%REVISION% %DATESTAMP%" > versio.inc

echo Compiling strateg0 first pass...
tools\sjasmplus --nologo --msg=war --i8080 strateg0.asm --lst=strateg0.lst --exp=strateg0.inc -DLZSIZE1=10000 -DLZSIZE2=6000
if errorlevel 1 goto Failed

dir /-c strateg0.bin|findstr /R /C:"strateg0.bin"

echo Compiling code...
tools\sjasmplus --nologo --msg=war --i8080 strateg1.asm --lst=strateg1.lst
if errorlevel 1 goto Failed

dir /-c strateg1.bin|findstr /R /C:"strateg1.bin"

tools\salvador.exe -classic strateg1.bin strateg1.zx0

dir /-c strateg1.zx0|findstr /R /C:"strateg1.zx0"

tools\salvador.exe -classic core/core.bin strateg2.zx0

dir /-c strateg2.zx0|findstr /R /C:"strateg2.zx0"

call :FileSize strateg1.zx0
set lz1size1=%fsize%

call :FileSize strateg2.zx0
set lzsize2=%fsize%

echo Compiling strateg0 second pass...
tools\sjasmplus --nologo --msg=war --i8080 strateg0.asm --lst=strateg0.lst --exp=strateg0.inc -DLZSIZE1=%lz1size1% -DLZSIZE2=%lzsize2%
if errorlevel 1 goto Failed

copy /b strateg0.bin+strateg1.zx0+strateg2.zx0 stratego.rom >nul

dir /-c stratego.rom|findstr /R /C:"stratego.rom"

echo %ESCchar%[92mSUCCESS%ESCchar%[0m
exit

:Failed
@echo off
echo %ESCchar%[91mFAILED%ESCchar%[0m
exit /b

:FileSize
set fsize=%~z1
exit /b 0
