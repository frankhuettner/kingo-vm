@echo off
rem =====================================================================
rem  Kingo classroom VM - one-time setup for Windows + VirtualBox.
rem  Put this file in the SAME folder as kingo-win-amd64.ova and
rem  double-click it. Safe to run again later: it just starts the VM.
rem =====================================================================
setlocal EnableDelayedExpansion
title Kingo VM Setup
set "VBM=%ProgramFiles%\Oracle\VirtualBox\VBoxManage.exe"
set "OVA=%~dp0kingo-win-amd64.ova"
set "VMNAME=KingoVM"

echo.
echo  === Kingo classroom VM setup ===
echo.

if not exist "%VBM%" (
    echo  VirtualBox is not installed yet. Trying automatic install...
    winget install -e --id Oracle.VirtualBox --accept-source-agreements --accept-package-agreements
    if not exist "%VBM%" (
        echo.
        echo  Automatic install did not work. Please:
        echo    1. Download VirtualBox from https://www.virtualbox.org/wiki/Downloads
        echo    2. Install it with all default settings
        echo    3. Double-click this file again
        echo.
        pause
        exit /b 1
    )
)

"%VBM%" showvminfo "%VMNAME%" >nul 2>&1
if not errorlevel 1 goto :startvm

if not exist "%OVA%" (
    echo  Cannot find kingo-win-amd64.ova next to this file.
    echo  Make sure both files are in the same folder and fully downloaded.
    pause
    exit /b 1
)

echo  Importing the VM - this takes a few minutes, please wait...
"%VBM%" import "%OVA%" --vsys 0 --vmname "%VMNAME%"
if errorlevel 1 (
    echo  Import failed. Ask your instructor for help ^(send a photo of this window^).
    pause
    exit /b 1
)

echo  Configuring network...
"%VBM%" modifyvm "%VMNAME%" --nic1 nat
for %%p in (8888 4040 7860 5678 3000 8978 6333 5432) do (
    "%VBM%" modifyvm "%VMNAME%" --natpf1 "svc%%p,tcp,127.0.0.1,%%p,,%%p"
)
"%VBM%" modifyvm "%VMNAME%" --natpf1 "ssh,tcp,127.0.0.1,2222,,22"

:startvm
echo  Starting the VM...
"%VBM%" startvm "%VMNAME%"
if errorlevel 1 (
    echo  Could not start the VM. Restart your computer and double-click this file again.
    pause
    exit /b 1
)

echo.
echo  ================================================================
echo   A VM window has opened. Wait until it says ALL SERVICES READY
echo   (1-3 minutes), then open these in your normal browser:
echo.
echo      Langflow    http://localhost:7860
echo      n8n         http://localhost:5678
echo      JupyterLab  http://localhost:8888
echo.
echo   Minimize the VM window while you work - do not close it.
echo  ================================================================
echo.
pause
