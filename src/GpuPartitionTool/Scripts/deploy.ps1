$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 参数通过环境变量传入（避免命令行转义问题）
$vmName      = $env:GPTOOL_VMNAME
$gpuInstance = $env:GPTOOL_GPUINSTANCE
$share       = [double]$env:GPTOOL_SHARE

$LowMmio  = 1GB
$HighMmio = 32GB

function Write-Json($obj) {
    Write-Output ('#JSON#' + ($obj | ConvertTo-Json -Compress -Depth 5))
}
function Out-Fail([string]$msg) {
    Write-Json ([PSCustomObject]@{ ok = $false; message = $msg; data = $null })
    exit 1
}
function Write-Step([string]$text) { Write-Output ("[部署] " + $text) }
function Scale([UInt64]$total, [double]$s) { return [UInt64]([decimal]$total * [decimal]$s) }

try {
    # S0 预校验
    Write-Step 'S0 预校验'
    $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
    if (-not $vm) { Out-Fail "找不到虚拟机：$vmName" }
    if ($share -le 0 -or $share -gt 1) { Out-Fail "分配比例必须在 (0,1] 区间" }
    $gpu = $null
    if (Get-Command Get-VMHostPartitionableGpu -ErrorAction SilentlyContinue) {
        $gpu = Get-VMHostPartitionableGpu -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq $gpuInstance } | Select-Object -First 1
    }
    if (-not $gpu -and (Get-Command Get-VMPartitionableGpu -ErrorAction SilentlyContinue)) {
        $gpu = Get-VMPartitionableGpu -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq $gpuInstance } | Select-Object -First 1
    }
    if (-not $gpu) {
        $gpu = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_PartitionableGpu -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq $gpuInstance } | Select-Object -First 1
    }
    if (-not $gpu) { Out-Fail "找不到可分区 GPU：$gpuInstance" }

    # S1 关闭虚拟机
    Write-Step 'S1 关闭虚拟机'
    if ($vm.State -ne 'Off') {
        Stop-VM -Name $vmName -Force
        $tries = 0
        $vm = Get-VM -Name $vmName
        while ($vm.State -ne 'Off' -and $tries -lt 30) { Start-Sleep -Seconds 2; $vm = Get-VM -Name $vmName; $tries++ }
        if ($vm.State -ne 'Off') { Out-Fail '虚拟机未能正常关闭，请手动关闭后再试' }
    }

    # S2 清理旧分区配置
    Write-Step 'S2 清理旧 GPU 分区配置'
    foreach ($a in (Get-VMGpuPartitionAdapter -VMName $vmName -ErrorAction SilentlyContinue)) {
        Remove-VMGpuPartitionAdapter -VMName $vmName -AdapterId $a.Id -ErrorAction SilentlyContinue
    }

    # S3 添加 GPU 分区（兼容 Server 2025 的 -InstancePath 与 Win10 22H2 的自动选择用法）
    Write-Step 'S3 添加 GPU 分区'
    $hasInstancePath = (Get-Command Add-VMGpuPartitionAdapter).Parameters.ContainsKey('InstancePath')
    $maxVRAM    = Scale $gpu.TotalVRAM $share
    $maxCompute = Scale $gpu.TotalCompute $share
    $maxDecode  = Scale $gpu.TotalDecode $share
    $params = @{
        MinPartitionVRAM    = 0; MaxPartitionVRAM = $maxVRAM; OptimalPartitionVRAM = $maxVRAM
        MinPartitionCompute = 0; MaxPartitionCompute = $maxCompute; OptimalPartitionCompute = $maxCompute
        MinPartitionDecode  = 0; MaxPartitionDecode = $maxDecode; OptimalPartitionDecode = $maxDecode
    }
    if ($gpu.TotalEncode -ne [UInt64]::MaxValue) {
        $maxEncode = Scale $gpu.TotalEncode $share
        $params += @{ MinPartitionEncode = 0; MaxPartitionEncode = $maxEncode; OptimalPartitionEncode = $maxEncode }
    }
    if ($hasInstancePath) {
        # Windows Server 2025：可精确指定 GPU 实例
        Add-VMGpuPartitionAdapter -VMName $vmName -InstancePath $gpu.Name -ErrorAction Stop
        Write-Step "S4 按 $([math]::Round($share * 100))% 比例设置显存/算力/编解码"
        Set-VMGpuPartitionAdapter -VMName $vmName @params -ErrorAction Stop | Out-Null
    }
    else {
        # Windows 10/11：不指定 InstancePath，直接在添加时设置分配参数（系统自动选择可分区 GPU）
        Write-Step "S4 按 $([math]::Round($share * 100))% 比例设置显存/算力/编解码（自动选择可分区 GPU）"
        Add-VMGpuPartitionAdapter -VMName $vmName @params -ErrorAction Stop | Out-Null
    }

    # S5 设置 MMIO 内存映射
    Write-Step 'S5 设置 MMIO 内存映射'
    Set-VM -VMName $vmName -GuestControlledCacheTypes $true -LowMemoryMappedIoSpace $LowMmio -HighMemoryMappedIoSpace $HighMmio -ErrorAction Stop

    # S6 解析宿主显卡驱动目录（失败仅警告，不致命）
    Write-Step 'S6 解析宿主显卡驱动目录'
    $GpuMatch = 'VEN_10DE'
    if     ($gpuInstance -match 'VEN_10DE') { $GpuMatch = 'VEN_10DE' }
    elseif ($gpuInstance -match 'VEN_1002') { $GpuMatch = 'VEN_1002' }
    elseif ($gpuInstance -match 'VEN_8086') { $GpuMatch = 'VEN_8086' }

    $driverDirs = @()
    try {
        $devIds = @()
        try {
            $devIds = Get-PnpDevice -Class Display -PresentOnly -ErrorAction Stop |
                Where-Object { $_.InstanceId -match $GpuMatch } |
                Select-Object -ExpandProperty InstanceId
        }
        catch { }
        if (-not $devIds) {
            $devIds = Get-CimInstance Win32_VideoController -ErrorAction Stop |
                Where-Object { $_.PNPDeviceID -match $GpuMatch } |
                Select-Object -ExpandProperty PNPDeviceID
        }
        if ($devIds) {
            $drivers = Get-CimInstance Win32_PnPSignedDriver -ErrorAction Stop |
                Where-Object { $devIds -contains $_.DeviceID } |
                Select-Object DeviceID, InfName, DriverName
            $infNames = $drivers | Where-Object { $_.InfName } | Select-Object -ExpandProperty InfName -Unique
            $sysDirs = $drivers | Where-Object { $_.DriverName } | ForEach-Object { Split-Path $_.DriverName -Parent } | Sort-Object -Unique
            $dism = Join-Path $env:WINDIR 'System32\dism.exe'
            # /english 强制英文输出，避免中文系统下 dism 的 GBK 输出被解码成乱码导致匹配失败
            $text = (& $dism /online /get-drivers /english 2>$null) -join "`n"
            $repoRoot = Join-Path $env:WINDIR 'System32\DriverStore\FileRepository'
            foreach ($pub in $infNames) {
                $pubEsc = [regex]::Escape($pub)
                $m = [regex]::Match($text, "(?ims)^\s*Published Name\s*[:：]\s*$pubEsc\s*$.*?^\s*Original File Name\s*[:：]\s*(?<orig>.+?)\s*$")
                if (-not $m.Success) { continue }
                $orig = $m.Groups['orig'].Value.Trim()
                if (-not $orig) { continue }
                $driverDirs += Get-ChildItem -LiteralPath $repoRoot -Directory -Filter "$orig`_*" -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty FullName
            }
            $driverDirs += $sysDirs
        }
    }
    catch { }
    $driverDirs = @($driverDirs | Sort-Object -Unique | Where-Object { $_ })
    if (-not $driverDirs) {
        Write-Step 'S6 未解析到驱动目录，将跳过驱动拷贝，请按教程手动拷贝'
    }
    else {
        Write-Step ("S6 找到驱动目录：" + ($driverDirs -join '; '))
    }

    # S7 启动虚拟机
    Write-Step 'S7 启动虚拟机'
    Start-VM -Name $vmName -ErrorAction Stop

    # S8 驱动拷贝（无凭据自动连接虚拟机）
    $driverSynced = $false
    if (-not $driverDirs) {
        Write-Step 'S8 未解析到驱动目录，跳过驱动拷贝'
    }
    else {
        Write-Step 'S8 等待虚拟机系统就绪（可能需 1-3 分钟）'
        $session = $null
        $ready = $false
        for ($i = 0; $i -lt 36; $i++) {
            Start-Sleep -Seconds 5
            try {
                # 无凭据：使用当前主机用户凭据连接（要求虚拟机内有同名管理员账户）
                # 若弹出系统凭据窗口，请在窗口中选择虚拟机内的管理员账户并确认
                $session = New-PSSession -VMName $vmName -ErrorAction Stop
                $ready = $true
                break
            }
            catch { }
        }
        if (-not $ready) {
            Write-Step 'S8 虚拟机系统长时间未就绪或连接失败，驱动未拷贝。可稍后重试，或手动将宿主显卡驱动目录拷贝到虚拟机 C:\Windows\System32\HostDriverStore\FileRepository 后重启虚拟机。'
        }
        else {
            Write-Step 'S8 虚拟机已就绪，开始拷贝显卡驱动'
            foreach ($d in $driverDirs) {
                if (-not $d) { continue }
                Write-Step ("S8 拷贝：" + (Split-Path $d -Leaf))
                Copy-Item -LiteralPath $d -Destination "C:\Windows\System32\HostDriverStore\FileRepository\$(Split-Path $d -Leaf)" -ToSession $session -Recurse -Force -ErrorAction Stop
            }
            Remove-PSSession $session -ErrorAction SilentlyContinue
            $driverSynced = $true
            Write-Step 'S8 驱动拷贝完成，重启虚拟机使驱动生效'
            Stop-VM -Name $vmName -Force
            $tries = 0
            $vm = Get-VM -Name $vmName
            while ($vm.State -ne 'Off' -and $tries -lt 30) { Start-Sleep -Seconds 2; $vm = Get-VM -Name $vmName; $tries++ }
            Start-VM -Name $vmName -ErrorAction Stop
        }
    }

    $tail = ''
    if ($driverSynced) { $tail = '显卡驱动已自动同步到虚拟机。' }
    elseif (-not $driverDirs) { $tail = '未解析到宿主显卡驱动目录，请手动拷贝显卡驱动到虚拟机 C:\Windows\System32\HostDriverStore\FileRepository 后重启虚拟机。' }
    else { $tail = '驱动未完成自动拷贝，请稍后重试部署，或手动拷贝显卡驱动目录后重启虚拟机。' }

    Write-Json ([PSCustomObject]@{
        ok      = $true
        message = "部署完成：GPU 分区已按 $([math]::Round($share * 100))% 分配，虚拟机已启动。$tail"
        data    = $null
    })
}
catch {
    $err = $_.Exception.Message
    # 内联回滚：清理 GPU 分区 + 恢复 MMIO
    try {
        Write-Output '[回滚] 清理 GPU 分区配置'
        $vmState = (Get-VM -Name $vmName -ErrorAction SilentlyContinue).State
        if ($vmState -and $vmState -ne 'Off') { Stop-VM -Name $vmName -Force -ErrorAction SilentlyContinue }
        foreach ($a in (Get-VMGpuPartitionAdapter -VMName $vmName -ErrorAction SilentlyContinue)) {
            Remove-VMGpuPartitionAdapter -VMName $vmName -AdapterId $a.Id -ErrorAction SilentlyContinue
        }
        Set-VM -VMName $vmName -GuestControlledCacheTypes $false -ErrorAction SilentlyContinue
    }
    catch { }
    Out-Fail "部署失败：$err ；已回滚清理 GPU 分区。虚拟机保持关机状态。"
}
