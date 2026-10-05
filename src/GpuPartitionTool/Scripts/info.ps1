$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Json($obj) {
    Write-Output ('#JSON#' + ($obj | ConvertTo-Json -Compress -Depth 6))
}

try {
    # 0. 检测 Hyper-V 是否启用（vmms 服务运行 = 已启用）
    $hypervEnabled = $false
    try {
        if ((Get-Service vmms -ErrorAction Stop).Status -eq 'Running') { $hypervEnabled = $true }
    } catch { }

    if (-not $hypervEnabled) {
        Write-Json ([PSCustomObject]@{
            ok      = $true
            message = 'Hyper-V 功能未启用'
            data    = [PSCustomObject]@{ hypervEnabled = $false; vms = @(); gpus = @() }
        })
        exit 0
    }

    # 1. 枚举虚拟机
    $vms = @()
    foreach ($vm in (Get-VM -ErrorAction Stop)) {
        $vms += [PSCustomObject]@{
            name             = $vm.Name
            state            = $vm.State.ToString()
            memoryAssignedMB = [long][math]::Round($vm.MemoryAssigned / 1MB)
            processorCount   = [int]$vm.ProcessorCount
        }
    }

    # 2. 枚举显卡（列出所有显示设备：NVIDIA/AMD/Intel 型号、物理显存、可分区标记）
    $gpus = @()
    $partObjs = @()
    try {
        if (Get-Command Get-VMHostPartitionableGpu -ErrorAction SilentlyContinue) {
            $partObjs = @(Get-VMHostPartitionableGpu -ErrorAction SilentlyContinue)
        }
        if (-not $partObjs -and (Get-Command Get-VMPartitionableGpu -ErrorAction SilentlyContinue)) {
            $partObjs = @(Get-VMPartitionableGpu -ErrorAction SilentlyContinue)
        }
        if (-not $partObjs) {
            $partObjs = @(Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_PartitionableGpu -ErrorAction SilentlyContinue)
        }
    }
    catch { }

    # 可分区 GPU 映射表：key = PCI 核心标识(VEN_x&DEV_y&SUBSYS_z&REV_x)，value = InstancePath
    $partMap = @{}
    foreach ($g in $partObjs) {
        $gInst = "$($g.Name)"
        if ($gInst -match 'PCI#([^#]+)#') { $partMap[$Matches[1]] = $gInst }
    }

    # 物理显存从注册表读取（qwMemorySize，字节）
    $classKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    $classProps = @()
    for ($i = 0; $i -lt 16; $i++) {
        $p = Get-ItemProperty ($classKey + '\00' + $i.ToString('D2')) -ErrorAction SilentlyContinue
        if ($p -and $p.DriverDesc) { $classProps += $p }
    }

    foreach ($dev in @(Get-PnpDevice -Class Display -PresentOnly -ErrorAction SilentlyContinue)) {
        $devId = "$($dev.InstanceId)"
        $vendor = '未知'
        if ($devId -match 'VEN_10DE') { $vendor = 'NVIDIA' }
        elseif ($devId -match 'VEN_1002') { $vendor = 'AMD' }
        elseif ($devId -match 'VEN_8086') { $vendor = 'Intel' }

        $friendly = $dev.FriendlyName
        if (-not $friendly) { $friendly = $vendor }

        # 是否可分区 + 对应 InstancePath
        $isPart = $false
        $instId = ''
        $gpuObj = $null
        $core = ''
        if ($devId -match '^PCI\\.*') {
            $core = ($devId -replace '^PCI\\', '') -replace '\\[0-9A-Fa-f].*$', ''
            if ($core -and $partMap.ContainsKey($core)) {
                $isPart = $true
                $instId = $partMap[$core]
                $gpuObj = $partObjs | Where-Object { "$($_.Name)" -eq $instId } | Select-Object -First 1
            }
        }

        # 物理显存（注册表 qwMemorySize）
        $physVRAM = 0
        foreach ($cp in $classProps) {
            $match = $false
            if ($cp.PNPDeviceID -and $cp.PNPDeviceID -eq $devId) { $match = $true }
            elseif ($cp.DriverDesc -eq $friendly) { $match = $true }
            if ($match) {
                $mem = $cp.'HardwareInformation.qwMemorySize'
                if ($mem -and [long]$mem -gt 0) { $physVRAM = [long]$mem; break }
            }
        }

        # 可分区配额参数
        $totalVRAM = 0; $totalCompute = 0; $totalDecode = 0; $totalEncode = -1
        if ($gpuObj) {
            $totalVRAM    = [long]$gpuObj.TotalVRAM
            $totalCompute = [long]$gpuObj.TotalCompute
            $totalDecode  = [long]$gpuObj.TotalDecode
            $totalEncode  = if ($gpuObj.TotalEncode -eq [UInt64]::MaxValue) { -1 } else { [long]$gpuObj.TotalEncode }
        }

        $gpus += [PSCustomObject]@{
            instanceId      = $instId
            name            = $friendly
            vendor          = $vendor
            status          = "$($dev.Status)"
            isPartitionable = $isPart
            physicalVRAM    = $physVRAM
            totalVRAM       = $totalVRAM
            totalCompute    = $totalCompute
            totalDecode     = $totalDecode
            totalEncode     = $totalEncode
        }
    }

    Write-Json ([PSCustomObject]@{
        ok      = $true
        message = 'OK'
        data    = [PSCustomObject]@{ hypervEnabled = $true; vms = $vms; gpus = $gpus }
    })
}
catch {
    Write-Json ([PSCustomObject]@{ ok = $false; message = $_.Exception.Message; data = $null })
    exit 1
}
