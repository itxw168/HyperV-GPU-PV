$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Json($obj) {
    Write-Output ('#JSON#' + ($obj | ConvertTo-Json -Compress -Depth 5))
}

try {
    # 检测是否已启用（vmms 服务运行 = 已启用）
    $enabled = $false
    try {
        if ((Get-Service vmms -ErrorAction Stop).Status -eq 'Running') { $enabled = $true }
    } catch { }

    if ($enabled) {
        Write-Json ([PSCustomObject]@{
            ok = $true; message = 'Hyper-V 已启用，无需操作'; data = [PSCustomObject]@{ reboot = $false }
        })
        exit 0
    }

    # 判断系统版本（家庭版需要绕过检查）
    $os = Get-CimInstance Win32_OperatingSystem
    $isHome = ($os.Caption -match 'Home|家庭')

    if ($isHome) {
        Write-Output '[开启] 检测到 Windows 家庭版，使用兼容方式安装 Hyper-V 组件包'
        $pkgs = Get-ChildItem "$env:SystemRoot\servicing\Packages\*Hyper-V*.mum" -ErrorAction SilentlyContinue
        if (-not $pkgs) { throw '找不到 Hyper-V 组件包（家庭版精简镜像可能不支持）' }
        $i = 0
        foreach ($p in $pkgs) {
            $i++
            Write-Output ("[开启] 安装组件 ($i/$($pkgs.Count))：" + $p.Name)
            & dism.exe /online /norestart /add-package:"$($p.FullName)" | Out-Null
        }
        Write-Output '[开启] 启用 Hyper-V 功能'
        $r = & dism.exe /online /enable-feature /featurename:Microsoft-Hyper-V -All /LimitAccess /All 2>&1
        Write-Output (($r | Where-Object { $_ -match '操作|complete|成功|percent|完成' }) -join "`n")
    }
    else {
        Write-Output '[开启] 启用 Hyper-V 功能（专业版/企业版）'
        $feat = Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All -NoRestart -ErrorAction Stop
        Write-Output ('[开启] ' + $feat.FeatureName + ' 状态: ' + $feat.State)
    }

    Write-Json ([PSCustomObject]@{
        ok      = $true
        message = 'Hyper-V 功能已开启，需要重启电脑后生效。重启后再打开本软件即可使用。'
        data    = [PSCustomObject]@{ reboot = $true }
    })
}
catch {
    Write-Json ([PSCustomObject]@{ ok = $false; message = '开启失败：' + $_.Exception.Message; data = $null })
    exit 1
}
