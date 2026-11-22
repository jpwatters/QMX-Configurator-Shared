@echo off
rem QMX+ Configurator launcher for Windows. Double-click it, or run it from a
rem Command Prompt (a snapshot .json can be given as an argument).
rem The first run creates a private Python environment (.venv-win) and installs
rem PySide6 and pyserial; later runs start the program straight away.
rem .venv-win is kept separate from the Mac's .venv so the same folder can be
rem used from both.
setlocal
cd /d "%~dp0"

rem Find Python 3: the py launcher first, then python on the PATH.
set "PY="
where py >nul 2>&1 && set "PY=py -3"
if not defined PY (
  where python >nul 2>&1 && set "PY=python"
)
if not defined PY goto :nopython
rem The Microsoft Store "python" alias exists even when Python is not installed,
rem so check that it really runs and is new enough.
%PY% -c "import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)" >nul 2>&1
if errorlevel 1 goto :nopython

set "VPY=.venv-win\Scripts\python.exe"
if not exist "%VPY%" (
  echo Setting up the Python environment ^(first run only^)...
  %PY% -m venv .venv-win
  if errorlevel 1 goto :fail
)

rem Install or update the packages when requirements.txt has changed.
fc /b requirements.txt .venv-win\requirements.installed >nul 2>&1
if errorlevel 1 (
  echo Installing PySide6 and pyserial...
  "%VPY%" -m pip install --upgrade pip >nul
  "%VPY%" -m pip install -r requirements.txt
  if errorlevel 1 goto :fail
  copy /y requirements.txt .venv-win\requirements.installed >nul
)

rem pythonw runs the program without leaving a console window open.
start "" ".venv-win\Scripts\pythonw.exe" qmx_configurator.py %*
exit /b 0

:nopython
echo Python 3.9 or newer was not found.
echo Install it from https://www.python.org/downloads/windows/
echo and tick "Add python.exe to PATH" in the installer, then run this again.
pause
exit /b 1

:fail
echo.
echo Setup failed - see the messages above. Check the internet connection
echo (the first run downloads PySide6 and pyserial) and run this again.
pause
exit /b 1
