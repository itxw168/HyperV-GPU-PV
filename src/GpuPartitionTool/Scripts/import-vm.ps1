$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 扫描 D:\Hyper-v 导入虚拟机（已注册的自动跳过）
$base = 'D:\Hyper-v'

function Write-Json($obj) {
    Write-Output ('#JSON#' + ($obj | ConvertTo-Json -Compress -Depth 5))
}

try {
    if (-not (Test-Path $base)) {
        Write-Json ([PSCustomObject]@{
            ok = $true; message = 'D:\Hyper-v 不存在，无需导入'; data = [PSCustomObject]@{ imported = @(); skipped = @() }
        })
        exit 0
    }

    # 已注册虚拟机名称集合
    $existing = @{}
    foreach ($vm in (Get-VM -ErrorAction SilentlyContinue)) { $existing["$($vm.Name)"] = $true }

    $imported = @()
    $skipped = @()

    # 扫描 .vmcx 配置文件
    $configs = @(Get-ChildItem $base -Recurse -Filter '*.vmcx' -ErrorAction SilentlyContinue | Select-Object -First 50)
    foreach ($c in $configs) {
        try {
            # 通过配置文件所在 VM 目录名判断名称
            $vmDir = Split-Path (Split-Path (Split-Path $c.FullName -Parent) -Parent) -Leaf
            $nameGuess = $vmDir
            if ($existing.ContainsKey($nameGuess)) { $skipped += $nameGuess; continue }

            # 直接导入；若提示已存在（ID 冲突），跳过
            $vm = Import-VM -Path $c.FullName -ErrorAction Stop
            $imported += $vm.Name
            $existing["$($vm.Name)"] = $true
            Write-Output ("[导入] 已导入虚拟机：" + $vm.Name)
        }
        catch {
            $msg = $_.Exception.Message
            if ($msg -match '已存在|already exists|重复') { $skipped += $nameGuess }
            else { Write-Output ("[导入] 跳过 $($c.FullName)：$msg") }
        }
    }

    $tail = ''
    if ($imported.Count -gt 0) { $tail = "新导入 $($imported.Count) 台：$($imported -join '、')。" }
    else { $tail = '没有发现需要导入的新虚拟机。' }

    Write-Json ([PSCustomObject]@{
        ok = $true; message = $tail
        data = [PSCustomObject]@{ imported = $imported; skipped = $skipped }
    })
}
catch {
    Write-Json ([PSCustomObject]@{ ok = $false; message = '导入失败：' + $_.Exception.Message; data = $null })
    exit 1
}
