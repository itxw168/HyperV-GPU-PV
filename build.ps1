# HyperV GPU-PV 显卡虚拟化工具 - 构建脚本（生成单文件 exe + 发行 zip）
# 用法: powershell -ExecutionPolicy Bypass -File build.ps1 [Debug|Release]
$ErrorActionPreference = 'Stop'

$dotnet = "$env:USERPROFILE\.dotnet\dotnet.exe"
if (-not (Test-Path $dotnet)) { $dotnet = 'dotnet' }

$config = if ($args[0]) { $args[0] } else { 'Release' }
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$proj = Join-Path $root 'src\GpuPartitionTool\GpuPartitionTool.csproj'
$out  = Join-Path $root 'publish'
$extra = Join-Path $root 'release-assets'

# 读取版本号（csproj 的 <Version>）
$ver = [regex]::Match([IO.File]::ReadAllText($proj), '<Version>([^<]+)</Version>').Groups[1].Value
if (-not $ver) { $ver = '0.0.0' }

# 单文件发布（不内置 .NET；脚本与原生库全部内嵌进 exe；注意 UPX 不可用于单文件 bundle）
& $dotnet publish $proj -c $config -r win-x64 --self-contained false -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o $out
if ($LASTEXITCODE -ne 0) { throw 'publish 失败' }

Remove-Item (Join-Path $out 'GpuPartitionTool.pdb') -Force -ErrorAction SilentlyContinue

# 复制发行附加文件（启动器 / 使用说明）
if (Test-Path $extra) {
    Copy-Item -Path (Join-Path $extra '*') -Destination $out -Force
}

# 生成发行压缩包（exe + 启动程序.bat + 使用说明.txt）
$zip = Join-Path $out ("HyperV-GPU-PV_v" + $ver + ".zip")
Remove-Item $zip -Force -ErrorAction SilentlyContinue
$zipItems = @()
foreach ($n in @('GpuPartitionTool.exe', '启动程序.bat', '使用说明.txt')) {
    $p2 = Join-Path $out $n
    if (Test-Path $p2) { $zipItems += $p2 }
}
if ($zipItems.Count -gt 0) {
    Compress-Archive -LiteralPath $zipItems -DestinationPath $zip -CompressionLevel Optimal -Force
}

Write-Output ""
Write-Output "发布完成：$out"
Write-Output "单文件：$out\GpuPartitionTool.exe（依赖已全部内嵌，需目标机器安装 .NET 8 Desktop Runtime）"
Write-Output "发行包：$zip"
Write-Output "日常使用请双击「启动程序.bat」（自动检测 .NET 8 运行时，缺失时引导到官网下载）"