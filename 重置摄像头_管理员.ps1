# 重置摄像头驱动（需要管理员权限）
# 作用：把摄像头设备彻底断电重新枚举，并重启 Windows 相机服务。
# 说明：这一步常用于修复“设备显示正常、但画面全黑”的驱动/固件卡死。

$ErrorActionPreference = 'Stop'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host '需要管理员权限，请右键「重置摄像头_管理员.bat」→ 以管理员身份运行。' -ForegroundColor Red
    Read-Host '按回车退出'
    exit 1
}

Write-Host ''
Write-Host '=== 重置摄像头 ===' -ForegroundColor Cyan
Write-Host ''

$cams = @(Get-PnpDevice -Class Camera -ErrorAction SilentlyContinue)
if ($cams.Count -eq 0) {
    Write-Host '没有找到摄像头设备（可能已从系统中消失）。' -ForegroundColor Red
    Read-Host '按回车退出'
    exit 1
}

foreach ($cam in $cams) {
    Write-Host ("找到设备： {0}" -f $cam.FriendlyName) -ForegroundColor Gray
    Write-Host ("  实例ID： {0}" -f $cam.InstanceId) -ForegroundColor DarkGray
    Write-Host '  正在禁用...' -ForegroundColor Gray
    try {
        Disable-PnpDevice -InstanceId $cam.InstanceId -Confirm:$false -ErrorAction Stop
    } catch {
        Write-Host ("  禁用失败：{0}" -f $_.Exception.Message) -ForegroundColor Yellow
        Write-Host '  改为尝试重启设备...' -ForegroundColor Gray
        & pnputil.exe /restart-device "$($cam.InstanceId)" | Out-Null
    }

    Start-Sleep -Seconds 3
    Write-Host '  正在启用...' -ForegroundColor Gray
    try {
        Enable-PnpDevice -InstanceId $cam.InstanceId -Confirm:$false -ErrorAction Stop
    } catch {
        Write-Host ("  启用失败：{0}，请到设备管理器手动启用。" -f $_.Exception.Message) -ForegroundColor Red
    }
    Start-Sleep -Seconds 2

    $after = Get-PnpDevice -InstanceId $cam.InstanceId -ErrorAction SilentlyContinue
    if ($after) {
        Write-Host ("  当前状态： {0}" -f $after.Status) -ForegroundColor Gray
    }
}

Write-Host ''
Write-Host '正在重启相机相关服务...' -ForegroundColor Gray
foreach ($svc in 'FrameServer', 'camsvc') {
    try {
        $s = Get-Service $svc -ErrorAction Stop
        if ($s.Status -eq 'Running') { Restart-Service $svc -Force -ErrorAction Stop }
        else { Start-Service $svc -ErrorAction Stop }
        Write-Host ("  {0} 已重启" -f $svc) -ForegroundColor Gray
    } catch {
        Write-Host ("  {0} 重启失败：{1}" -f $svc, $_.Exception.Message) -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host '完成。现在请重新打开摄像头软件，或运行「双击运行检测.bat」验证。' -ForegroundColor Green
Read-Host '按回车退出'
