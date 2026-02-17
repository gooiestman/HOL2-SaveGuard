@echo off
title HOL2 SaveGuard
cd /d "%~dp0"
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0HOL2_SaveGuard.ps1"
pause
