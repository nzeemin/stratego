@echo off
set rt11dsk=C:\bin\rt11dsk

del x-ukncbtl\stratego.dsk
@if exist "x-ukncbtl\stratego.dsk" (
  echo.
  echo ####### FAILED to delete old disk image file #######
  exit /b
)
copy x-ukncbtl\sys1002ex.dsk stratego.dsk
%rt11dsk% a stratego.dsk build\STRATE.SAV
move stratego.dsk x-ukncbtl\stratego.dsk

@if not exist "x-ukncbtl\stratego.dsk" (
  echo ####### ERROR disk image file not found #######
  exit /b
)

start x-ukncbtl\UKNCBTL.exe /boot
