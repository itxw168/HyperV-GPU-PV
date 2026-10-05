$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 参数（环境变量）
$vmName = $env:GPTOOL_NEWVM_NAME
$memGB  = [int]$env:GPTOOL_NEWVM_MEM
$cpu    = [int]$env:GPTOOL_NEWVM_CPU
$diskGB = [int]$env:GPTOOL_NEWVM_DISK
$iso    = $env:GPTOOL_NEWVM_ISO
$base   = 'D:\Hyper-v'

function Write-Json($obj) {
    Write-Output ('#JSON#' + ($obj | ConvertTo-Json -Compress -Depth 5))
}
function Out-Fail([string]$msg) {
    Write-Json ([PSCustomObject]@{ ok = $false; message = $msg; data = $null })
    exit 1
}

try {
    if ([string]::IsNullOrWhiteSpace($vmName)) { Out-Fail '虚拟机名称不能为空' }
    if ($memGB -lt 1) { $memGB = 8 }
    if ($cpu -lt 1) { $cpu = 4 }
    if ($diskGB -lt 20) { $diskGB = 80 }

    # 重名检查
    if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) { Out-Fail "已存在同名虚拟机：$vmName" }

    # 检查 D 盘是否存在
    if (-not (Test-Path 'D:\')) { Out-Fail '未检测到 D 盘，无法使用 D:\Hyper-v 作为存储位置' }

    # 创建目录
    New-Item -ItemType Directory -Force -Path $base | Out-Null

    # 设置 Hyper-V 默认路径（虚拟机配置与虚拟硬盘）
    Write-Output '[创建] 设置 Hyper-V 默认存储路径为 D:\Hyper-v'
    Set-VMHost -VirtualMachinePath $base -VirtualHardDiskPath $base -ErrorAction SilentlyContinue

    # 主机级增强会话
    Write-Output '[创建] 启用主机增强会话模式'
    Set-VMHost -EnableEnhancedSessionMode $true -ErrorAction SilentlyContinue

    # 创建第二代虚拟机
    Write-Output ("[创建] 创建虚拟机 $vmName（第2代 / ${memGB}GB 内存 / ${cpu}核 / ${diskGB}GB 磁盘）")
    $vhd = Join-Path $base "$vmName.vhdx"
    New-VM -Name $vmName -Generation 2 `
        -MemoryStartupBytes ([long]$memGB * 1GB) `
        -NewVHDPath $vhd -NewVHDSizeBytes ([long]$diskGB * 1GB) `
        -SwitchName 'Default Switch' -Path $base -ErrorAction Stop | Out-Null

    # GPU 虚拟化要求：关闭动态内存，设静态内存
    Set-VM -Name $vmName -DynamicMemory:$false -MemoryStartupBytes ([long]$memGB * 1GB) -ProcessorCount $cpu -ErrorAction Stop
    Write-Output '[创建] 已配置静态内存（GPU 虚拟化要求）'

    # VM 级增强会话（第2代默认支持，确保开启）
    Set-VM -Name $vmName -EnhancedSessionTransportType HvSocket -ErrorAction SilentlyContinue
    Write-Output '[创建] 已开启增强会话'

    # 挂载 ISO（可选）
    if (-not [string]::IsNullOrWhiteSpace($iso)) {
        if (-not (Test-Path $iso)) { Out-Fail "找不到 ISO 镜像：$iso" }
        Write-Output ("[创建] 挂载安装镜像：" + (Split-Path $iso -Leaf))
        Add-VMDvdDrive -VMName $vmName -Path $iso -ErrorAction Stop
        $dvd = Get-VMDvdDrive -VMName $vmName | Select-Object -First 1
        Set-VMFirmware -VMName $vmName -FirstBootDevice $dvd -ErrorAction Stop
        Write-Output '[创建] 已设置从 DVD 启动（开机需按任意键进入安装）'
    }

    Write-Json ([PSCustomObject]@{
        ok      = $true
        message = "虚拟机 $vmName 创建成功（存储于 $base）。$(if ($iso) { 'ISO 已挂载，可直接开机安装系统。' } else { '未挂载 ISO，装系统时请在设置中添加安装镜像。' })"
        data    = $null
    })
}
catch {
    Write-Json ([PSCustomObject]@{ ok = $false; message = '创建失败：' + $_.Exception.Message; data = $null })
    exit 1
}
