@echo off
setlocal
powershell.exe -NoProfile -Command "if ((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 } else { exit 1 }" >nul 2>&1
if errorlevel 1 (
  echo ERROR: Run this command from an elevated CMD window on the IPC.
  pause
  exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "& 'D:\OEM\Adapter\setup_gleason_ipc.ps1'"
if errorlevel 1 (
  echo ERROR: Scoped IPC setup failed. Preserve the error and setup state for diagnosis.
  pause
  exit /b 1
)

echo Scoped IPC setup completed. Retry the WinRM connection from the build host.
pause
exit /b 0
