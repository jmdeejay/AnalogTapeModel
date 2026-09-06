@echo off
rem ===========================================================================
rem  Bundles the built plug-in for a GitHub release.
rem
rem    make-release.bat                 packs the Release builds as 1.0.0
rem    make-release.bat 1.0.1           packs them as 1.0.1
rem    make-release.bat 1.0.1 Debug     packs the Debug builds instead
rem
rem  Produces, in release\:
rem
rem    ChowTapeModel-<version>-Win32-VST2.4.zip
rem    ChowTapeModel-<version>-Win64-VST2.4.zip
rem
rem  The version and the architecture are on the archive; the DLL inside keeps
rem  its plain name. Hosts key their plug-in lists and project references on
rem  the DLL's path, so a name that changed every release would look to them
rem  like a different plug-in each time.
rem
rem  The licence travels with the binary, as the GPL asks.
rem ===========================================================================

setlocal EnableDelayedExpansion

set "VERSION=%~1"
if "%VERSION%"=="" set "VERSION=1.0.0"

set "CONFIG=%~2"
if "%CONFIG%"=="" set "CONFIG=Release"

set "ROOT=%~dp0"
set "OUT=%ROOT%release"

if not exist "%OUT%" mkdir "%OUT%"

echo.
echo Packing ChowTapeModel %VERSION% (%CONFIG%)
echo.

set FAILED=0
call :pack Win32
call :pack Win64

echo.
if "%FAILED%"=="1" (
  echo Finished with errors -- build the missing configuration and run again.
  endlocal
  exit /b 1
)

echo Done. The two archives are in:
echo   %OUT%
echo.
echo Attach both to the release, and tag it v%VERSION%.
endlocal
exit /b 0

rem ---------------------------------------------------------------------------
:pack
set "ARCH=%~1"
set "SRC=%ROOT%bin\%ARCH%\%CONFIG%\ChowTapeModel.dll"
set "NAME=ChowTapeModel-%VERSION%-%ARCH%-VST2.4"
set "STAGE=%OUT%\%NAME%"

if not exist "%SRC%" (
  echo   [ !! ] %ARCH%: not built -- %SRC%
  set FAILED=1
  goto :eof
)

if exist "%STAGE%" rmdir /s /q "%STAGE%"
mkdir "%STAGE%"

copy /y "%SRC%" "%STAGE%\ChowTapeModel.dll" >nul
if errorlevel 1 (
  echo   [ !! ] %ARCH%: could not copy the DLL
  set FAILED=1
  goto :eof
)

if exist "%ROOT%LICENSE" copy /y "%ROOT%LICENSE" "%STAGE%\" >nul
if exist "%ROOT%README.md" copy /y "%ROOT%README.md" "%STAGE%\" >nul

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "Compress-Archive -Path '%STAGE%\*' -DestinationPath '%OUT%\%NAME%.zip' -Force"
if errorlevel 1 (
  echo   [ !! ] %ARCH%: could not write the archive
  set FAILED=1
  goto :eof
)

rem the staging folder has served its purpose; the archive is what ships
rmdir /s /q "%STAGE%"

for %%F in ("%OUT%\%NAME%.zip") do echo   [ ok ] %NAME%.zip  (%%~zF bytes)
goto :eof
