@echo off
set YV7_HOME=%~dp0
if exist "%~dp0.venv\Scripts\python.exe" ("%~dp0.venv\Scripts\python.exe" -m yv7 %*) else (python -m yv7 %*)
