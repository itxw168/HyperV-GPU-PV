@echo off
setlocal
title Hyper-V 显卡虚拟化部署工具 - 启动器

set "EXE=%~dp0GpuPartitionTool.exe"
if not exist "%EXE%" (
    echo [错误] 未找到 GpuPartitionTool.exe，请确认与启动器放在同一目录。
    pause
    exit /b 1
)

rem ---- 检测 .NET 8 Desktop Runtime（注册表方式） ----
set "HAS_RT="
reg query "HKLM\SOFTWARE\dotnet\Setup\InstalledVersions\x64\DesktopRuntime" /s 2>nul | findstr /r "DesktopRuntime\\8\." >nul 2>nul
if not errorlevel 1 set "HAS_RT=1"

rem ---- 注册表未命中时，用 dotnet 命令补充检测 ----
if not defined HAS_RT (
    where dotnet >nul 2>nul
    if not errorlevel 1 (
        dotnet --list-runtimes 2>nul | findstr /i "Microsoft.WindowsDesktop.App 8" >nul 2>nul
        if not errorlevel 1 set "HAS_RT=1"
    )
)

if defined HAS_RT goto :run

echo.
echo   未检测到 .NET 8 桌面运行时（.NET Desktop Runtime 8.x）。
echo   本程序运行需要该运行库。
echo.
echo   正在为你打开微软官方下载页面...
start "" "https://dotnet.microsoft.com/download/dotnet/8.0"
echo.
echo   请安装 ".NET Desktop Runtime 8.x (x64)"，
echo   安装完成后重新双击本启动器即可打开程序。
echo.
pause
exit /b 1

:run
start "" "%EXE%"
exit /b 0
