@echo off
setlocal
rem Opens the camera AIR page in a separate Chrome/Edge profile that keeps running when the game window covers it.
set "URL=http://localhost:8090/"
if not "%~1"=="" set "URL=http://localhost:%~1/"
set "PROFILE=%LOCALAPPDATA%\Brokenithm-CameraAir"
set "BROWSER="
if exist "%ProgramFiles%\Google\Chrome\Application\chrome.exe" set "BROWSER=%ProgramFiles%\Google\Chrome\Application\chrome.exe"
if not defined BROWSER if exist "%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe" set "BROWSER=%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe"
if not defined BROWSER if exist "%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe" set "BROWSER=%LOCALAPPDATA%\Google\Chrome\Application\chrome.exe"
if not defined BROWSER if exist "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" set "BROWSER=%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
if not defined BROWSER if exist "%ProgramFiles%\Microsoft\Edge\Application\msedge.exe" set "BROWSER=%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"
if not defined BROWSER (
  echo Chrome or Edge was not found. Open %URL% manually.
  pause
  exit /b 1
)
start "" "%BROWSER%" --user-data-dir="%PROFILE%" --no-first-run --disable-backgrounding-occluded-windows --disable-renderer-backgrounding --disable-background-timer-throttling --app=%URL%
