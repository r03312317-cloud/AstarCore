@echo off
setlocal
chcp 65001 >nul
set "PYTHONUTF8=1"
set "PYTHONUNBUFFERED=1"
set "YOLO_PYTHON=D:\anaconda\pythonw.exe"
if not exist "%YOLO_PYTHON%" (
  echo Python GUI runtime not found: %YOLO_PYTHON%
  pause
  exit /b 1
)
start "" "%YOLO_PYTHON%" -B -X utf8 "%~dp0video_window.py" %*
exit /b 0
