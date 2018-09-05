@echo off

echo Uninstalling for %USERNAME%
echo.

echo Checking for and removing existing tasks
echo.

schtasks /query /tn HeroesShareWatcher > NUL 2>&1
if %ERRORLEVEL% EQU 1 goto Check1

echo Removing existing watcher task...
@echo on
schtasks /end /tn HeroesShareWatcher
schtasks /delete /f /tn HeroesShareWatcher
@echo off

:Check1

schtasks /query /tn HeroesShareUpdater > NUL 2>&1
if %ERRORLEVEL% EQU 1 goto Check2

echo Removing existing updater task...
@echo on
schtasks /end /tn HeroesShareUpdater
schtasks /delete /f /tn HeroesShareUpdater
@echo off

:Check2

echo Removing application directory...
if exist "%APPDATA%\Heroes Share\" rmdir /s /q "%APPDATA%\Heroes Share\"

echo.

echo Complete! Quitting in 30 seconds
timeout /t 30 > NUL
