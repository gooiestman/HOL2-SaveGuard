@echo off
title HOL2 SaveGuard - Auto-Start Setup
echo.
echo  =============================================
echo   HOL2 SaveGuard - Auto-Start Setup
echo  =============================================
echo.
echo  This will create a shortcut in your Startup folder
echo  so SaveGuard runs automatically when you log in.
echo.
echo  [1] Add to Startup (run on login)
echo  [2] Remove from Startup
echo  [3] Cancel
echo.
set /p choice="  Choose option: "

if "%choice%"=="1" goto install
if "%choice%"=="2" goto remove
goto end

:install
set "STARTUP=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
set "SCRIPT=%~dp0Launch_SaveGuard.bat"
set "SHORTCUT=%STARTUP%\HOL2_SaveGuard.lnk"

powershell -NoProfile -Command "$ws = New-Object -ComObject WScript.Shell; $s = $ws.CreateShortcut('%SHORTCUT%'); $s.TargetPath = '%SCRIPT%'; $s.WorkingDirectory = '%~dp0'; $s.Description = 'HOL2 SaveGuard - Auto Backup'; $s.WindowStyle = 7; $s.Save()"

if exist "%SHORTCUT%" (
    echo.
    echo  [OK] Auto-start shortcut created!
    echo  SaveGuard will run when you log in.
    echo  Shortcut: %SHORTCUT%
) else (
    echo.
    echo  [ERROR] Failed to create shortcut.
)
goto end

:remove
set "SHORTCUT=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\HOL2_SaveGuard.lnk"
if exist "%SHORTCUT%" (
    del "%SHORTCUT%"
    echo.
    echo  [OK] Auto-start removed.
) else (
    echo.
    echo  Auto-start shortcut not found. Nothing to remove.
)
goto end

:end
echo.
pause
