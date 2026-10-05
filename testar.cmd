@echo off
setlocal
cd /d %~dp0
call "C:\Program Files (x86)\Embarcadero\Studio\20.0\bin\rsvars.bat"
if not exist bin mkdir bin
if not exist dcu mkdir dcu
dcc32 -Q -B -Ebin -N0dcu -Usrc;tests -U"%BDS%\source\DUnitX;%BDS%\lib\win32\release" -NSSystem;Winapi;Vcl tests\Testes.dpr
if errorlevel 1 exit /b 1
bin\Testes.exe
exit /b %ERRORLEVEL%
