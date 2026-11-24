@echo off
rem Copies the finished package (build\out) to a folder, for example C:\openEMS, and checks it.
rem    install_package.cmd [target]       target defaults to C:\openEMS
rem build\out is complete and self-contained (exe, DLLs, bin\, venv\Scripts\ with its own Python): it can also
rem be copied by hand to another computer. Close KiCad first. Details: install_package.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_package.ps1" %*
exit /b %errorlevel%
