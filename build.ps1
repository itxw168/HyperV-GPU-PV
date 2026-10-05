# Hyper-V 显卡虚拟化部署工具 - 构建脚本
# 用法:  powershell -ExecutionPolicy Bypass -File build.ps1 [Debug|Release]
$ErrorActionPreference = 'Stop'

$dotnet = "$env:USERPROFILE\.dotnet\dotnet.exe"
if (-not (Test-Path $dotnet)) { $dotnet = 'dotnet' }

$config = if ($args[0]) { $args[0] } else { 'Release' }
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$proj = Join-Path $root 'src\GpuPartitionTool\GpuPartitionTool.csproj'
$out  = Join-Path $root 'publish'

# 单文件发布（不内置 .NET；脚本与原生库全部内嵌进 exe；注意 UPX 不可用于单文件 bundle）
& $dotnet publish $proj -c $config -r win-x64 --self-contained false -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o $out
if ($LASTEXITCODE -ne 0) { throw 'publish 失败' }

Remove-Item (Join-Path $out 'GpuPartitionTool.pdb') -Force -ErrorAction SilentlyContinue

Write-Output ""
Write-Output "发布完成：$out"
Write-Output "单个可执行文件：$out\GpuPartitionTool.exe（约 235KB，依赖已全部内嵌）"
Write-Output "日常使用请双击「启动程序.bat」（自动检测 .NET 8 运行时，缺失时引导到官网下载）"
