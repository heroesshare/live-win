@echo off

echo Installing for %USERNAME%
echo.

echo Checking for and removing existing tasks
echo .

schtasks /query /tn HeroesShareWatcher > NUL 2>&1
if %ERRORLEVEL% EQU 1 goto Check1

echo Removing existing watcher task...
schtasks /end /tn HeroesShareWatcher
schtasks /delete /f /tn HeroesShareWatcher

:Check1

schtasks /query /tn HeroesShareUpdater > NUL 2>&1
if %ERRORLEVEL% EQU 1 goto Check1

echo Removing existing updater task...
schtasks /end /tn HeroesShareUpdater
schtasks /delete /f /tn HeroesShareUpdater

:Check2

echo Creating application directory...
if not exist "%APPDATA%\Heroes Share\" mkdir "%APPDATA%\Heroes Share\"
echo.

echo Copying files...
@echo on
copy /y "%~dp0rejoinprotocol.exe" "%APPDATA%\Heroes Share\"
copy /y "%~dp0watcher.ps1" "%APPDATA%\Heroes Share\"
copy /y "%~dp0updater.ps1" "%APPDATA%\Heroes Share\"
copy /y "%~dp0version.txt" "%APPDATA%\Heroes Share\"

@echo off
echo.


:Check3
echo Creating the scheduled tasks

@echo on
schtasks /create /np /tn HeroesShareWatcher /xml "%~dp0WatcherTask.xml"
schtasks /create /np /tn HeroesShareWatcher /xml "%~dp0UpdaterTask.xml"

@echo off
timeout /t 30 > NUL