param([string]$DeviceId)

$ErrorActionPreference = 'Stop'
$sdkRoot = $env:ANDROID_SDK_ROOT
if (-not $sdkRoot) { $sdkRoot = $env:ANDROID_HOME }
if (-not $sdkRoot) { $sdkRoot = Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
$adb = Join-Path $sdkRoot 'platform-tools/adb.exe'
if (-not (Test-Path -LiteralPath $adb)) { throw "ADB not found at $adb" }

if (-not $DeviceId) {
    $devices = @(& $adb devices | ForEach-Object {
        if ($_ -match '^(\S+)\s+device\b') { $Matches[1] }
    })
    if ($devices.Count -ne 1) {
        throw 'Connect and authorize one device, or pass -DeviceId from adb devices.'
    }
    $DeviceId = $devices[0]
}

$frekiPid = (& $adb -s $DeviceId shell pidof com.frekihub.freki_hub | Out-String).Trim()
if (-not $frekiPid) { throw 'Open FrekiHub on the device, then run this command again.' }
$frekiPid = $frekiPid.Split(' ')[0]
$logDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) '.tmp/logs'
New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
$logFile = Join-Path $logDirectory ('freki-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
Write-Host "Capturing FrekiHub logs from $DeviceId to $logFile"
Write-Host 'Reproduce the error, then press Ctrl+C. Restart capture if the app process restarts.'
& $adb -s $DeviceId logcat -v threadtime "--pid=$frekiPid" 'flutter:V' 'AndroidRuntime:E' '*:S' | Tee-Object -FilePath $logFile
if ($LASTEXITCODE -ne 0) { throw 'ADB log capture ended with an error.' }
