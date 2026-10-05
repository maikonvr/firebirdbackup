@echo off
setlocal
cd /d %~dp0
call "C:\Program Files (x86)\Embarcadero\Studio\20.0\bin\rsvars.bat"
if not exist bin mkdir bin
if not exist dcu mkdir dcu
brcc32 recursos\app.rc -foFirebirdBackup.res
if errorlevel 1 exit /b 1
dcc32 -Q -B -$O+ -$D- -Ebin -N0dcu -Usrc -Rsrc -U"%BDS%\lib\win32\release" -NSSystem;Winapi;Vcl;Vcl.Imaging FirebirdBackup.dpr
exit /b %ERRORLEVEL%
