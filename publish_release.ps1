[CmdletBinding()]
param(
    [string]$Version,
    [ValidateSet('patch', 'minor', 'major', 'build')]
    [string]$Bump = 'patch',
    [string]$Notes,
    [string]$NotesFile,
    [string]$DeviceId,
    [string]$GitHubToken,
    [switch]$SkipInstall,
    [switch]$SkipSync,
    [switch]$SkipGitHubRelease,
    [switch]$SkipGitPush,
    [switch]$ForceVersion,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$ProjectRoot = $PSScriptRoot
$PubspecPath = Join-Path $ProjectRoot 'pubspec.yaml'
$GeoapifyConfigPath = Join-Path $ProjectRoot 'config\geoapify.local.json'
$UpdateConfigPath = Join-Path $ProjectRoot 'config\update.local.json'
$ReleaseConfigPath = Join-Path $ProjectRoot 'config\release.local.json'
$ApkPath = Join-Path $ProjectRoot 'build\app\outputs\flutter-apk\app-release.apk'
$FrxnanceSyncScript = Join-Path (Split-Path -Parent $ProjectRoot) 'Frekihub - Frxnance.app\sync_from_frekihub.ps1'

function Write-Step([string]$Title) {
    Write-Host "`n==> $Title" -ForegroundColor Cyan
}

function Expand-HomePath([string]$RawPath) {
    if ([string]::IsNullOrWhiteSpace($RawPath)) { return '' }
    $p = $RawPath.Trim()
    if ($p -eq '~' -or $p -eq '$HOME') { return $HOME }
    if ($p -match '^(?:~|\$HOME)[/\\](.+)$') {
        return Join-Path $HOME $Matches[1]
    }
    return $p
}

function Resolve-GitHubRepo([string]$RawSource) {
    $s = if ($RawSource) { $RawSource.Trim() } else { '' }
    if ($s -match '^([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$') {
        return $Matches[1]
    }
    if ($s -match 'github\.com[:/]([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git|/releases.*|/)?$') {
        return $Matches[1]
    }
    $remote = (& git -C $ProjectRoot remote get-url origin 2>$null | Out-String).Trim()
    if ($remote -match 'github\.com[:/]([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?$') {
        return $Matches[1]
    }
    throw 'Could not determine GitHub owner/repo from config/update.local.json or git remote origin.'
}

function Get-GitHubAuthToken([psobject]$LocalConfig) {
    if (-not [string]::IsNullOrWhiteSpace($GitHubToken)) { return $GitHubToken.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) { return $env:GITHUB_TOKEN.Trim() }
    if (-not [string]::IsNullOrWhiteSpace($env:GH_TOKEN)) { return $env:GH_TOKEN.Trim() }
    if ($LocalConfig -and $LocalConfig.PSObject.Properties['githubToken'] -and -not [string]::IsNullOrWhiteSpace([string]$LocalConfig.githubToken)) {
        return ([string]$LocalConfig.githubToken).Trim()
    }
    $ghCmd = Get-Command gh -ErrorAction SilentlyContinue
    if ($ghCmd) {
        $ghTok = (& $ghCmd.Source auth token 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($ghTok)) {
            return $ghTok
        }
    }
    $credInput = "protocol=https`nhost=github.com`n`n"
    $credOutput = $credInput | & git -C $ProjectRoot credential fill 2>$null
    if ($LASTEXITCODE -eq 0 -and $credOutput) {
        foreach ($line in ($credOutput -split "`r?`n")) {
            if ($line -match '^password=(.+)$') {
                return $Matches[1].Trim()
            }
        }
    }
    throw 'No GitHub token found. Sign in with Git Credential Manager, set $env:GITHUB_TOKEN, or set "githubToken" in config/release.local.json.'
}

function Invoke-GitHubJson([string]$Method, [string]$Uri, [string]$Token, [hashtable]$Body = $null) {
    $headers = @{
        'Accept'               = 'application/vnd.github+json'
        'Authorization'        = "Bearer $Token"
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent'           = 'FrekiHub-Release-Publisher'
    }
    $prevProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        if ($null -ne $Body) {
            $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 6 -Compress))
            return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -ContentType 'application/json; charset=utf-8' -Body $jsonBytes
        }
        return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers
    } finally {
        $ProgressPreference = $prevProgress
    }
}

Push-Location $ProjectRoot
try {
    # 0. Pre-flight checks
    Write-Step 'Checking release prerequisites'

    if (-not (Test-Path -LiteralPath $PubspecPath)) {
        throw "pubspec.yaml not found at $PubspecPath"
    }
    if (-not (Test-Path -LiteralPath $GeoapifyConfigPath)) {
        throw "Missing $GeoapifyConfigPath (copy config/geoapify.example.json and set GEOAPIFY_API_KEY)."
    }
    if (-not (Test-Path -LiteralPath $UpdateConfigPath)) {
        throw "Missing $UpdateConfigPath (copy config/update.example.json and set UPDATE_URL)."
    }
    $updateCfg = Get-Content -LiteralPath $UpdateConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $updateCfg.UPDATE_URL -or [string]::IsNullOrWhiteSpace([string]$updateCfg.UPDATE_URL)) {
        throw 'config/update.local.json must define a non-empty UPDATE_URL so installed APKs know where to check for updates.'
    }

    $localReleaseCfg = $null
    if (Test-Path -LiteralPath $ReleaseConfigPath) {
        $localReleaseCfg = Get-Content -LiteralPath $ReleaseConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    $keystorePathRaw = if ($env:FREKIHUB_KEYSTORE_PATH) { $env:FREKIHUB_KEYSTORE_PATH }
                       elseif ($localReleaseCfg -and $localReleaseCfg.keystorePath) { [string]$localReleaseCfg.keystorePath }
                       else { '~/frekihub-release.jks' }
    $keystorePath = Expand-HomePath $keystorePathRaw

    $keystorePassword = if ($env:FREKIHUB_KEYSTORE_PASSWORD) { $env:FREKIHUB_KEYSTORE_PASSWORD }
                        elseif ($localReleaseCfg -and $localReleaseCfg.keystorePassword) { [string]$localReleaseCfg.keystorePassword }
                        else { '' }

    $keyAlias = if ($env:FREKIHUB_KEY_ALIAS) { $env:FREKIHUB_KEY_ALIAS }
                elseif ($localReleaseCfg -and $localReleaseCfg.keyAlias) { [string]$localReleaseCfg.keyAlias }
                else { 'frekihub' }

    $keyPassword = if ($env:FREKIHUB_KEY_PASSWORD) { $env:FREKIHUB_KEY_PASSWORD }
                   elseif ($localReleaseCfg -and $localReleaseCfg.keyPassword) { [string]$localReleaseCfg.keyPassword }
                   else { $keystorePassword }

    if (-not $DryRun) {
        if (-not (Test-Path -LiteralPath $keystorePath)) {
            throw "Release keystore not found at: $keystorePath"
        }
        if ([string]::IsNullOrWhiteSpace($keystorePassword) -or $keystorePassword -eq 'CHANGE_ME') {
            throw 'Release keystore password is not configured. Set config/release.local.json or $env:FREKIHUB_KEYSTORE_PASSWORD.'
        }
        if ([string]::IsNullOrWhiteSpace($keyPassword) -or $keyPassword -eq 'CHANGE_ME') {
            throw 'Release key password is not configured. Set config/release.local.json or $env:FREKIHUB_KEY_PASSWORD.'
        }
    }

    $repo = Resolve-GitHubRepo ([string]$updateCfg.UPDATE_URL)

    # Check ADB & device before starting long build
    $adbPath = $null
    $resolvedDevice = $DeviceId
    if (-not $resolvedDevice -and $localReleaseCfg -and $localReleaseCfg.deviceId) {
        $resolvedDevice = ([string]$localReleaseCfg.deviceId).Trim()
    }
    if (-not $SkipInstall) {
        $sdkRoot = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT }
                   elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME }
                   else { Join-Path $env:LOCALAPPDATA 'Android\Sdk' }
        $adbPath = Join-Path $sdkRoot 'platform-tools\adb.exe'
        if (-not $DryRun) {
            if (-not (Test-Path -LiteralPath $adbPath)) {
                throw "ADB not found at $adbPath. Pass -SkipInstall or install Android SDK platform-tools."
            }
            $connectedDevices = @(& $adbPath devices | ForEach-Object {
                if ($_ -match '^(\S+)\s+device\b') { $Matches[1] }
            })
            if ($resolvedDevice) {
                if ($connectedDevices -notcontains $resolvedDevice) {
                    $onlineList = if ($connectedDevices.Count -gt 0) { $connectedDevices -join ', ' } else { 'none' }
                    throw "ADB device '$resolvedDevice' is not connected/authorized (online: $onlineList). Connect it, pass -DeviceId, or pass -SkipInstall."
                }
            } elseif ($connectedDevices.Count -eq 1) {
                $resolvedDevice = $connectedDevices[0]
            } else {
                throw 'Connect one authorized Android device, set "deviceId" in config/release.local.json, or pass -DeviceId / -SkipInstall.'
            }
        }
    }

    if (-not $SkipSync -and -not (Test-Path -LiteralPath $FrxnanceSyncScript)) {
        throw "Companion sync script not found at $FrxnanceSyncScript (or pass -SkipSync)."
    }

    $resolvedGhToken = $null
    if (-not $SkipGitHubRelease -and -not $DryRun) {
        $resolvedGhToken = Get-GitHubAuthToken $localReleaseCfg
    }

    # 1. Resolve version bump & monotonic versionCode
    Write-Step 'Resolving version and versionCode'

    $pubspecRaw = Get-Content -LiteralPath $PubspecPath -Raw -Encoding UTF8
    $verMatch = [regex]::Match($pubspecRaw, '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?\s*$')
    if (-not $verMatch.Success) {
        throw 'Could not parse "version: X.Y.Z+N" in pubspec.yaml.'
    }

    $curMajor = [int]$verMatch.Groups[1].Value
    $curMinor = [int]$verMatch.Groups[2].Value
    $curPatch = [int]$verMatch.Groups[3].Value
    $curCode = if ($verMatch.Groups[4].Success) { [int]$verMatch.Groups[4].Value } else { 0 }
    $curVersionFull = "$curMajor.$curMinor.$curPatch+$curCode"

    $maxTagCode = 0
    $allTags = @(& git -C $ProjectRoot tag --list 2>$null)
    foreach ($t in $allTags) {
        if ($t -match '\+(\d+)$') {
            $tc = [int]$Matches[1]
            if ($tc -gt $maxTagCode) { $maxTagCode = $tc }
        }
    }

    $remoteLatestCode = 0
    try {
        $prevProg = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        $latestHeaders = @{ 'Accept' = 'application/vnd.github+json'; 'User-Agent' = 'FrekiHub-Release-Publisher' }
        if ($resolvedGhToken) { $latestHeaders['Authorization'] = "Bearer $resolvedGhToken" }
        $remoteLatest = Invoke-RestMethod -Method Get -Uri "https://api.github.com/repos/$repo/releases/latest" -Headers $latestHeaders -TimeoutSec 5
        if ($remoteLatest -and $remoteLatest.tag_name -match '\+(\d+)$') {
            $remoteLatestCode = [int]$Matches[1]
        } elseif ($remoteLatest -and $remoteLatest.body -match '(?i)(?:versionCode|build)\s*[:=]\s*(\d+)') {
            $remoteLatestCode = [int]$Matches[1]
        }
    } catch {
        # Offline or no existing release yet; local pubspec and Git tags still guard monotonicity.
    } finally {
        $ProgressPreference = $prevProg
    }

    $highestKnownCode = [Math]::Max($curCode, [Math]::Max($maxTagCode, $remoteLatestCode))
    $autoNextCode = $highestKnownCode + 1

    if (-not [string]::IsNullOrWhiteSpace($Version)) {
        $cleanVer = $Version.Trim() -replace '^[vV]', ''
        if ($cleanVer -match '^(\d+\.\d+\.\d+)\+(\d+)$') {
            $newVersionName = $Matches[1]
            $newCode = [int]$Matches[2]
        } elseif ($cleanVer -match '^(\d+\.\d+\.\d+)$') {
            $newVersionName = $Matches[1]
            $newCode = $autoNextCode
        } else {
            throw "Invalid -Version '$Version'. Expected X.Y.Z or X.Y.Z+N (e.g. 1.6.1+$autoNextCode)."
        }
    } else {
        switch ($Bump) {
            'major' { $newVersionName = "$($curMajor + 1).0.0" }
            'minor' { $newVersionName = "$curMajor.$($curMinor + 1).0" }
            'patch' { $newVersionName = "$curMajor.$curMinor.$($curPatch + 1)" }
            'build' { $newVersionName = "$curMajor.$curMinor.$curPatch" }
        }
        $newCode = $autoNextCode
    }

    if (-not $ForceVersion -and $newCode -le $highestKnownCode) {
        throw "New versionCode (+$newCode) must be greater than highest existing versionCode (+$highestKnownCode) so installed APKs detect and allow the upgrade. Use +$autoNextCode (or pass -ForceVersion to override)."
    }

    $newVersionFull = "$newVersionName+$newCode"
    $releaseTag = "v$newVersionFull"

    if (-not $ForceVersion -and ($allTags -contains $releaseTag)) {
        throw "Git tag '$releaseTag' already exists locally. Choose a higher version or delete the local tag if it was never published."
    }

    # Resolve release notes
    if (-not [string]::IsNullOrWhiteSpace($NotesFile)) {
        if (-not (Test-Path -LiteralPath $NotesFile)) {
            throw "NotesFile not found: $NotesFile"
        }
        $releaseNotes = (Get-Content -LiteralPath $NotesFile -Raw -Encoding UTF8).Trim()
    } elseif (-not [string]::IsNullOrWhiteSpace($Notes)) {
        $releaseNotes = $Notes.Trim()
    } else {
        $lastTag = (& git -C $ProjectRoot describe --tags --abbrev=0 2>$null | Out-String).Trim()
        $logRange = if ($LASTEXITCODE -eq 0 -and $lastTag) { "$lastTag..HEAD" } else { '-n 10' }
        $rawSubjects = @(& git -C $ProjectRoot log $logRange --no-merges --pretty=format:'%s' 2>$null)
        $bullets = @(
            $rawSubjects |
                Where-Object { $_ -and $_ -notmatch '^v?\d+\.\d+\.\d+(?:\+\d+)?$' } |
                ForEach-Object { "- $($_.Trim())" }
        )
        $releaseNotes = if ($bullets.Count -gt 0) {
            ($bullets -join "`n")
        } else {
            "- Maintenance and stability improvements."
        }
    }

    Write-Host "Current pubspec : $curVersionFull (highest known versionCode: $highestKnownCode)"
    Write-Host "Next version    : $newVersionFull"
    Write-Host "GitHub tag      : $releaseTag on $repo"
    Write-Host "ADB target      : $(if ($SkipInstall) { 'skipped (-SkipInstall)' } else { $resolvedDevice })"
    Write-Host "Frxnance sync   : $(if ($SkipSync) { 'skipped (-SkipSync)' } else { 'enabled (-Verify)' })"
    Write-Host "Release notes   :`n$releaseNotes"

    if ($DryRun) {
        Write-Step 'Dry run complete (no files modified, no APK built, no release published)'
        return
    }

    # Update pubspec.yaml
    Write-Step "Updating pubspec.yaml -> version: $newVersionFull"
    $updatedPubspec = [regex]::Replace(
        $pubspecRaw,
        '(?m)^version:\s*\d+\.\d+\.\d+(?:\+\d+)?(?=\r?$)',
        "version: $newVersionFull",
        1
    )
    [System.IO.File]::WriteAllText($PubspecPath, $updatedPubspec, [System.Text.UTF8Encoding]::new($false))

    # 2. Build signed release APK
    Write-Step 'Building signed release APK with Geoapify + Update defines'
    $prevStore = $env:FREKIHUB_KEYSTORE_PATH
    $prevStorePass = $env:FREKIHUB_KEYSTORE_PASSWORD
    $prevAlias = $env:FREKIHUB_KEY_ALIAS
    $prevKeyPass = $env:FREKIHUB_KEY_PASSWORD
    try {
        $env:FREKIHUB_KEYSTORE_PATH = $keystorePath
        $env:FREKIHUB_KEYSTORE_PASSWORD = $keystorePassword
        $env:FREKIHUB_KEY_ALIAS = $keyAlias
        $env:FREKIHUB_KEY_PASSWORD = $keyPassword

        & flutter build apk --release `
            --dart-define-from-file=config/geoapify.local.json `
            --dart-define-from-file=config/update.local.json
        if ($LASTEXITCODE -ne 0) {
            throw "flutter build apk --release failed with exit code $LASTEXITCODE."
        }
    } finally {
        $env:FREKIHUB_KEYSTORE_PATH = $prevStore
        $env:FREKIHUB_KEYSTORE_PASSWORD = $prevStorePass
        $env:FREKIHUB_KEY_ALIAS = $prevAlias
        $env:FREKIHUB_KEY_PASSWORD = $prevKeyPass
    }

    if (-not (Test-Path -LiteralPath $ApkPath)) {
        throw "Expected release APK not found at $ApkPath"
    }
    $apkSizeMb = [Math]::Round((Get-Item -LiteralPath $ApkPath).Length / 1MB, 2)
    Write-Host "Built APK: $ApkPath ($apkSizeMb MiB)" -ForegroundColor Green

    # 3. Commit pubspec bump, tag, push & publish GitHub Release
    if (-not $SkipGitPush) {
        Write-Step "Committing pubspec.yaml, tagging $releaseTag, and pushing to origin"
        $pubspecDiff = (& git -C $ProjectRoot status --porcelain -- pubspec.yaml | Out-String).Trim()
        if ($pubspecDiff) {
            & git -C $ProjectRoot commit --only -m $releaseTag -- pubspec.yaml
            if ($LASTEXITCODE -ne 0) { throw 'git commit failed for pubspec.yaml.' }
        }
        & git -C $ProjectRoot tag $releaseTag
        if ($LASTEXITCODE -ne 0) { throw "git tag $releaseTag failed." }

        & git -C $ProjectRoot push origin HEAD $releaseTag
        if ($LASTEXITCODE -ne 0) { throw "git push origin HEAD $releaseTag failed." }
    }

    if (-not $SkipGitHubRelease) {
        Write-Step "Publishing GitHub Release $releaseTag on $repo"
        $targetSha = (& git -C $ProjectRoot rev-parse HEAD | Out-String).Trim()

        $existingList = Invoke-GitHubJson -Method 'Get' -Uri "https://api.github.com/repos/$repo/releases?per_page=30" -Token $resolvedGhToken
        $draftOrExisting = $null
        if ($existingList) {
            $draftOrExisting = $existingList | Where-Object { $_.tag_name -eq $releaseTag } | Select-Object -First 1
        }

        if ($draftOrExisting) {
            $release = Invoke-GitHubJson -Method 'Patch' -Uri "https://api.github.com/repos/$repo/releases/$($draftOrExisting.id)" -Token $resolvedGhToken -Body @{
                tag_name   = $releaseTag
                name       = "FrekiHub $newVersionName"
                body       = $releaseNotes
                prerelease = $false
            }
            foreach ($asset in @($release.assets)) {
                if ($asset.name -eq 'app-release.apk') {
                    $null = Invoke-GitHubJson -Method 'Delete' -Uri "https://api.github.com/repos/$repo/releases/assets/$($asset.id)" -Token $resolvedGhToken
                }
            }
        } else {
            # Create as draft first so /releases/latest never serves a release before app-release.apk finishes uploading.
            $createBody = @{
                tag_name   = $releaseTag
                name       = "FrekiHub $newVersionName"
                body       = $releaseNotes
                draft      = $true
                prerelease = $false
            }
            if (-not $SkipGitPush -and $targetSha) {
                $createBody['target_commitish'] = $targetSha
            }
            $release = Invoke-GitHubJson -Method 'Post' -Uri "https://api.github.com/repos/$repo/releases" -Token $resolvedGhToken -Body $createBody
        }

        $uploadBase = ($release.upload_url -replace '\{\?.*$', '')
        $uploadUri = "${uploadBase}?name=app-release.apk"
        Write-Host "Uploading app-release.apk ($apkSizeMb MiB) to GitHub Releases..."
        $uploadHeaders = @{
            'Accept'               = 'application/vnd.github+json'
            'Authorization'        = "Bearer $resolvedGhToken"
            'X-GitHub-Api-Version' = '2022-11-28'
            'User-Agent'           = 'FrekiHub-Release-Publisher'
        }
        $prevProgress = $ProgressPreference
        $ProgressPreference = 'SilentlyContinue'
        try {
            $uploadedAsset = Invoke-RestMethod -Method Post -Uri $uploadUri -Headers $uploadHeaders -ContentType 'application/vnd.android.package-archive' -InFile $ApkPath
        } finally {
            $ProgressPreference = $prevProgress
        }
        if (-not $uploadedAsset -or $uploadedAsset.state -ne 'uploaded') {
            throw 'GitHub asset upload did not report state=uploaded.'
        }

        $published = Invoke-GitHubJson -Method 'Patch' -Uri "https://api.github.com/repos/$repo/releases/$($release.id)" -Token $resolvedGhToken -Body @{
            draft       = $false
            prerelease  = $false
            make_latest = 'true'
        }
        Write-Host "Published latest release: $($published.html_url)" -ForegroundColor Green
    }

    # 4. Install release APK on connected ADB device
    if (-not $SkipInstall) {
        Write-Step "Installing app-release.apk onto device $resolvedDevice"
        & $adbPath -s $resolvedDevice install -r $ApkPath
        if ($LASTEXITCODE -ne 0) {
            throw "adb install failed on device $resolvedDevice with exit code $LASTEXITCODE."
        }
    }

    # 5. Sync & verify standalone Frxnance companion app
    if (-not $SkipSync) {
        Write-Step 'Syncing and verifying companion app (Frekihub - Frxnance.app)'
        & $FrxnanceSyncScript -Verify
        if ($LASTEXITCODE -ne 0) {
            throw "sync_from_frekihub.ps1 -Verify failed with exit code $LASTEXITCODE."
        }
    }

    Write-Step "All done! Shipped $releaseTag (Version $newVersionName ($newCode))"
} finally {
    Pop-Location
}
