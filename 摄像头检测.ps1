# 摄像头画面检测工具
# 作用：直接向摄像头取一帧画面，判断是否真的全黑，并保存预览图。
# 用法：双击同目录下的「双击运行检测.bat」，或在 PowerShell 中运行本脚本。

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
Add-Type -AssemblyName System.Drawing

$asTaskOp = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]
$asTaskAction = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
    $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and
    $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncAction' })[0]
function AwaitOp([object]$op, [Type]$t) {
    $task = $asTaskOp.MakeGenericMethod($t).Invoke($null, @($op))
    $null = $task.Wait(30000)
    return $task.Result
}
function AwaitAction([object]$a) {
    $task = $asTaskAction.Invoke($null, @($a))
    $null = $task.Wait(30000)
}

[Windows.Devices.Enumeration.DeviceInformation, Windows.Devices.Enumeration, ContentType = WindowsRuntime] | Out-Null
[Windows.Media.Capture.MediaCapture, Windows.Media, ContentType = WindowsRuntime] | Out-Null
[Windows.Media.Capture.MediaCaptureInitializationSettings, Windows.Media, ContentType = WindowsRuntime] | Out-Null
[Windows.Media.MediaProperties.ImageEncodingProperties, Windows.Media, ContentType = WindowsRuntime] | Out-Null
[Windows.Storage.Streams.InMemoryRandomAccessStream, Windows.Storage, ContentType = WindowsRuntime] | Out-Null

Write-Host ''
Write-Host '=== 摄像头画面检测 ===' -ForegroundColor Cyan
Write-Host ''

# 请保持环境光线正常，不要遮挡镜头
$devices = AwaitOp ([Windows.Devices.Enumeration.DeviceInformation]::FindAllAsync([Windows.Devices.Enumeration.DeviceClass]::VideoCapture)) ([Windows.Devices.Enumeration.DeviceInformationCollection])
if ($devices.Count -eq 0) {
    Write-Host '没有找到任何摄像头设备。' -ForegroundColor Red
    Read-Host '按回车退出'
    exit 1
}
foreach ($d in $devices) { Write-Host ("设备： {0}" -f $d.Name) -ForegroundColor Gray }

$settings = New-Object Windows.Media.Capture.MediaCaptureInitializationSettings
$settings.StreamingCaptureMode = [Windows.Media.Capture.StreamingCaptureMode]::Video
$settings.VideoDeviceId = $devices[0].Id
$settings.SharingMode = [Windows.Media.Capture.MediaCaptureSharingMode]::SharedReadOnly
$mc = New-Object Windows.Media.Capture.MediaCapture
try {
    AwaitAction ($mc.InitializeAsync($settings))
} catch {
    Write-Host '无法打开摄像头，可能被其他程序占用（如微信/QQ/浏览器会议）。请先关闭这些程序。' -ForegroundColor Red
    Read-Host '按回车退出'
    exit 1
}

function Get-FrameInfo([string]$fileName) {
    $st = New-Object Windows.Storage.Streams.InMemoryRandomAccessStream
    $enc = [Windows.Media.MediaProperties.ImageEncodingProperties]::CreateJpeg()
    AwaitAction ($mc.CapturePhotoToStreamAsync($enc, $st))
    $st.Seek(0)
    $len = [int]$st.Size
    $bytes = New-Object byte[] $len
    $r = New-Object Windows.Storage.Streams.DataReader($st)
    $null = AwaitOp ($r.LoadAsync([uint32]$len)) ([uint32])
    $r.ReadBytes($bytes); $r.Dispose()

    $ms = New-Object System.IO.MemoryStream (,$bytes)
    $bmp = New-Object System.Drawing.Bitmap($ms)
    $bmp.Save((Join-Path $PSScriptRoot $fileName), [System.Drawing.Imaging.ImageFormat]::Png)
    $sum = 0.0; $n = 0; $lo = 255; $hi = 0
    for ($y = 0; $y -lt $bmp.Height; $y += 4) {
        for ($x = 0; $x -lt $bmp.Width; $x += 4) {
            $p = $bmp.GetPixel($x, $y)
            $l = 0.299 * $p.R + 0.587 * $p.G + 0.114 * $p.B
            $sum += $l; $n++
            if ($l -lt $lo) { $lo = $l }
            if ($l -gt $hi) { $hi = $l }
        }
    }
    $bmp.Dispose()
    return [pscustomobject]@{ Mean = ($sum / $n); Low = $lo; High = $hi; Spread = ($hi - $lo) }
}

Write-Host ''
Write-Host '正在取画面（请稍等 2 秒）...' -ForegroundColor Gray
$f = $null
foreach ($i in 1..3) { $f = Get-FrameInfo '摄像头预览.png'; Start-Sleep -Milliseconds 400 }

Write-Host ''
Write-Host ("平均亮度 : {0:N1} / 255" -f $f.Mean)
Write-Host ("亮度范围 : {0:N1} ~ {1:N1}（差值 {2:N1}）" -f $f.Low, $f.High, $f.Spread)
Write-Host ''

if ($f.Spread -lt 8 -and $f.Mean -lt 100) {
    Write-Host '结论：画面基本是均匀的一片，没有任何景物细节。' -ForegroundColor Yellow
    Write-Host '      说明传感器几乎没有接收到光线，而不是“画面偏暗”。' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '请依次检查：' -ForegroundColor Cyan
    Write-Host '  1. 摄像头镜头上是否有可滑动的物理遮挡盖板（很多笔记本屏幕顶上有个小滑块）'
    Write-Host '  2. 键盘上是否有摄像头快捷键（常见 Fn + F10 / Fn + F6），按一次切换'
    Write-Host '  3. 机械革命电竞控制台里是否有“摄像头”开关'
    Write-Host '  4. 用管理员身份运行「重置摄像头_管理员.bat」后再测一次'
}
elseif ($f.Mean -lt 40) {
    Write-Host '结论：画面能看出景物，但整体很暗。建议开灯或增加环境光后再测。' -ForegroundColor Yellow
}
else {
    Write-Host '结论：摄像头工作正常，画面有正常的明暗细节。' -ForegroundColor Green
    Write-Host '      如果某个软件里还是黑屏，那是该软件自身的问题（可用「设置 > 隐私和安全性 > 相机」检查该应用的权限）。'
}

$mc.Dispose()
Write-Host ''
Write-Host '预览图已保存为：摄像头预览.png' -ForegroundColor Gray
Read-Host '按回车退出'
