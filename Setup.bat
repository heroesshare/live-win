@echo off

REM check for elevation
REM https://winaero.com/blog/how-to-check-in-a-batch-file-if-you-are-running-it-elevated/

openfiles > NUL 2>&1
if %ERRORLEVEL% EQU 0 goto Proceed
echo You must Right-click and use 'Run as Administrator'
pause
exit

:Proceed 
echo Installing for %USERNAME%
echo.

echo Creating application directory...
if not exist "%APPDATA%\Heroes Share\" mkdir "%APPDATA%\Heroes Share\"
echo.

echo Copying files...
@echo on
copy /y "%~dp0rejoinprotocol.exe" "%APPDATA%\Heroes Share\"
copy /y "%~dp0watcher.ps1" "%APPDATA%\Heroes Share\"
@echo off
echo.


REM check for and remove existing task

schtasks /query /tn HeroesShareWatcher > NUL 2>&1
if %ERRORLEVEL% EQU 1 goto Create

echo Removing existing task...
schtasks /end /tn HeroesShareWatcher
schtasks /delete /f /tn HeroesShareWatcher

REM install scheduled task

:Create
echo You will have to authenticate to add the scheduled task
pause

@echo on
schtasks /create /ru %USERNAME% /tn HeroesShareWatcher /xml "%~dp0ScheduledTask.xml"

@echo off
pause