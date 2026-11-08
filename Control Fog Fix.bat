@echo off
setlocal
title Control DX11 Fog Fix
cd /d "%~dp0"

if "%~1"=="" goto menu

set "GAME_DIR="
if /i "%~nx1"=="Control_DX11.exe" set "GAME_DIR=%~dp1"
if exist "%~f1\Control_DX11.exe" set "GAME_DIR=%~f1"

if not defined GAME_DIR goto bad_drop

echo Control game folder: "%GAME_DIR%"
echo Installing the DX11 fog fix...
call :run Install "%GAME_DIR%"
exit /b %errorlevel%

:bad_drop
echo.
echo That is not the Control game folder or Control_DX11.exe.
echo Drag Control_DX11.exe onto this file and try again.
echo.
pause
exit /b 1

:menu
cls
echo ========================================
echo          Control DX11 Fog Fix
echo ========================================
echo.
echo   1. Install the fix
echo   2. Check installation status
echo   3. Restore the original shaders
echo   4. Exit
echo.
choice /c 1234 /n /m "Choose an option: "

if errorlevel 4 exit /b 0
if errorlevel 3 goto restore
if errorlevel 2 goto status
if errorlevel 1 goto install

:install
call :run Install
goto menu

:status
call :run Status
goto menu

:restore
echo.
echo This will restore the original shader files from the installer's backup.
choice /c YN /n /m "Continue? [Y/N]: "
if errorlevel 2 goto menu
call :run Restore
goto menu

:run
set "RUN_ACTION=%~1"
set "RUN_FOLDER=%~2"
echo.
if defined RUN_FOLDER (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ControlFogPatch.ps1" -Action %RUN_ACTION% -GameFolder "%RUN_FOLDER%"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ControlFogPatch.ps1" -Action %RUN_ACTION%
)
set "RUN_RESULT=%errorlevel%"
echo.
if not "%RUN_RESULT%"=="0" (
    echo The operation did not complete. Read the message above for what to do next.
) else (
    echo Finished successfully.
)
echo.
pause
exit /b %RUN_RESULT%
