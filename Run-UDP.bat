@echo off
rem UDP (Ultimate Debloat Pack) launcher.
rem Starts UDP.ps1 with Windows PowerShell 5.1. "-ExecutionPolicy Bypass" applies to this process
rem only; the system execution policy is not changed. UDP.ps1 asks for administrator rights itself.
setlocal
set "UDP_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
set "UDP_SCRIPT=%~dp0UDP.ps1"

if not exist "%UDP_SCRIPT%" (
    echo UDP.ps1 was not found next to this file. Extract the whole UDP folder first.
    pause
    exit /b 1
)

"%UDP_PS%" -NoProfile -ExecutionPolicy Bypass -File "%UDP_SCRIPT%" %*
endlocal
