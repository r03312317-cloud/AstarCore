@echo off
setlocal
pushd "%~dp0"
if exist "%~dp0runtime\python.exe" if exist "%~dp0runtime\pythonw.exe" (
  "%~dp0runtime\python.exe" -B "%~dp0preflight.py"
  if not errorlevel 1 (
    start "" "%~dp0runtime\pythonw.exe" "%~dp0start_linux.py"
    exit /b 0
  )
)
if exist "D:\anaconda\python.exe" if exist "D:\anaconda\pythonw.exe" (
  "D:\anaconda\python.exe" -B "%~dp0preflight.py"
  if not errorlevel 1 (
    start "" "D:\anaconda\pythonw.exe" "%~dp0start_linux.py"
    exit /b 0
  )
)
where pythonw.exe >nul 2>nul
if not errorlevel 1 (
  python.exe -B "%~dp0preflight.py"
  if not errorlevel 1 (
    start "" pythonw.exe "%~dp0start_linux.py"
    exit /b 0
  )
)
where pyw.exe >nul 2>nul
if not errorlevel 1 (
  py.exe -3 -B "%~dp0preflight.py"
  if not errorlevel 1 (
    start "" pyw.exe -3 "%~dp0start_linux.py"
    exit /b 0
  )
)
echo A working Python 3.9 or newer with tkinter was not found.
echo The bundled application includes pyserial; no pip install is required.
pause
exit /b 1
