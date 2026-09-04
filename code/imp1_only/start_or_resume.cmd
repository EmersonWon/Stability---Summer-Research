@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_or_resume.ps1" -Workers 8
pause
