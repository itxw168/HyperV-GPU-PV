$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$vmName = $env:GPTOOL_VMNAME

function Write-Json($obj) {
    Write-Output ('#JSON#' + ($obj | ConvertTo-Json -Compress -Depth 5))
}

try {
    $vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
    if (-not $vm) {
        Write-Json ([PSCustomObject]@{ ok = $false; message = "找不到虚拟机：$vmName"; data = $null })
        exit 1
    }
    $wasRunning = ($vm.State -eq 'Running')
    $wasSaved   = ($vm.State -eq 'Saved')

    # 关闭虚拟机
    if ($vm.State -ne 'Off') {
        Write-Output '[卸载] 关闭虚拟机'
        Stop-VM -Name $vmName -Force
        $tries = 0
        $vm = Get-VM -Name $vmName
        while ($vm.State -ne 'Off' -and $tries -lt 30) { Start-Sleep -Seconds 2; $vm = Get-VM -Name $vmName; $tries++ }
    }

    # 移除 GPU 分区
    Write-Output '[卸载] 移除 GPU 分区'
    foreach ($a in (Get-VMGpuPartitionAdapter -VMName $vmName -ErrorAction SilentlyContinue)) {
        Remove-VMGpuPartitionAdapter -VMName $vmName -AdapterId $a.Id -ErrorAction SilentlyContinue
    }

    # 恢复 MMIO 设置
    Write-Output '[卸载] 恢复 MMIO 设置'
    Set-VM -VMName $vmName -GuestControlledCacheTypes $false -ErrorAction SilentlyContinue

    # 还原虚拟机启动状态
    if ($wasRunning -or $wasSaved) {
        Write-Output '[卸载] 恢复虚拟机启动状态'
        Start-VM -Name $vmName -ErrorAction Stop
    }

    Write-Json ([PSCustomObject]@{
        ok      = $true
        message = '卸载完成：GPU 分区已移除，MMIO 已恢复。'
        data    = $null
    })
}
catch {
    Write-Json ([PSCustomObject]@{ ok = $false; message = '卸载失败：' + $_.Exception.Message; data = $null })
    exit 1
}
