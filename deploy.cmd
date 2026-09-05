@echo off
rem Copies the built plug-in into a VST folder.
rem
rem   deploy.cmd "C:\Program Files\VSTPlugins" [Win32^|Win64]
rem
rem The STN networks and the Roboto Condensed faces are linked into the DLL, so
rem there is nothing to copy alongside it.

setlocal
if "%~1"=="" (
  echo usage: deploy.cmd ^<target folder^> [Win32^|Win64]
  exit /b 1
)

set TARGET=%~1
set PLATFORM=%~2
if "%PLATFORM%"=="" set PLATFORM=Win64

set SRC=%~dp0bin\%PLATFORM%\Release
if not exist "%SRC%\ChowTapeModel.dll" (
  echo Could not find "%SRC%\ChowTapeModel.dll" -- build the %PLATFORM% Release target first.
  exit /b 1
)

if not exist "%TARGET%" mkdir "%TARGET%"
copy /y "%SRC%\ChowTapeModel.dll" "%TARGET%" >nul 2>nul
if errorlevel 1 (
  echo Could not copy the DLL. Is it loaded in a running host?
  exit /b 1
)

echo Deployed %PLATFORM% build to "%TARGET%".
endlocal
