$ProgressPreference = 'SilentlyContinue'

$Version = "1.0.0"
$CatalogUrl = "https://raw.githubusercontent.com/iMrLopez/headunit-adb-scripts/refs/heads/main/app-catalog.json"
$NoCacheHeaders = @{ 'Cache-Control' = 'no-cache'; 'Pragma' = 'no-cache' }

$TempDir = Join-Path $env:TEMP ([System.IO.Path]::GetRandomFileName())
New-Item -ItemType Directory -Path $TempDir | Out-Null
$AdbCmd = $null
$_Completed = $false

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                                                      ║" -ForegroundColor Cyan
Write-Host "║    " -ForegroundColor Cyan -NoNewline
Write-Host "Head Unit ADB Script" -ForegroundColor White -NoNewline
Write-Host "                             ║" -ForegroundColor Cyan
Write-Host "║    ADB-based Android APK installer for head units    ║" -ForegroundColor Cyan
Write-Host "║                                                      ║" -ForegroundColor Cyan
Write-Host "║                              " -ForegroundColor Cyan -NoNewline
Write-Host "by iMrLopez · 2025" -ForegroundColor DarkCyan -NoNewline
Write-Host "      ║" -ForegroundColor Cyan
Write-Host "║                                              " -ForegroundColor Cyan -NoNewline
Write-Host "v$Version" -ForegroundColor DarkCyan -NoNewline
Write-Host "  ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

Write-Host "Using temp directory: $TempDir"

function Invoke-Download {
    param([string]$Uri, [string]$OutFile, [string]$Label)
    $client = New-Object System.Net.WebClient
    $global:_dlDone = $false
    $global:_dlError = $null
    Register-ObjectEvent -InputObject $client -EventName DownloadProgressChanged -SourceIdentifier "_dlProgress" -Action {
        $pct      = $EventArgs.ProgressPercentage
        $received = [math]::Round($EventArgs.BytesReceived / 1MB, 1)
        $total    = [math]::Round($EventArgs.TotalBytesToReceive / 1MB, 1)
        Write-Progress -Activity $Label -Status "$received MB / $total MB" -PercentComplete $pct
    } | Out-Null
    Register-ObjectEvent -InputObject $client -EventName DownloadFileCompleted -SourceIdentifier "_dlDone" -Action {
        $global:_dlDone = $true
        if ($EventArgs.Error) { $global:_dlError = $EventArgs.Error }
    } | Out-Null
    try {
        $client.DownloadFileAsync([Uri]$Uri, $OutFile)
        while (-not $global:_dlDone) { Start-Sleep -Milliseconds 100 }
        Write-Progress -Activity $Label -Completed
        if ($global:_dlError) { throw $global:_dlError }
    } finally {
        Unregister-Event -SourceIdentifier "_dlProgress" -ErrorAction SilentlyContinue
        Unregister-Event -SourceIdentifier "_dlDone"     -ErrorAction SilentlyContinue
        $client.Dispose()
        Remove-Variable _dlDone, _dlError -Scope Global -ErrorAction SilentlyContinue
    }
}

function Invoke-Cleanup {
    if ($TempDir -and (Test-Path $TempDir)) {
        Remove-Item -Recurse -Force $TempDir
    }
}

try {
    # ── App selection ────────────────────────────────────────────────────────

    Write-Host "Fetching app catalog..."
    $Apps = (Invoke-WebRequest -Uri $CatalogUrl -UseBasicParsing -Headers $NoCacheHeaders).Content | ConvertFrom-Json

    Write-Host "Available apps to install:"
    for ($i = 0; $i -lt $Apps.Count; $i++) {
        Write-Host "  $($i + 1)) $($Apps[$i].name)  [$($Apps[$i].type)]"
    }
    Write-Host ""
    $SelectionInput = Read-Host "Select apps to install (e.g. 1 2 3 or 'all')"

    $SelectedIndices = @()
    if ($SelectionInput.Trim() -eq "all") {
        $SelectedIndices = 0..($Apps.Count - 1)
    } else {
        foreach ($token in ($SelectionInput -split '[,\s]+')) {
            if ($token -match '^\d+$') {
                $n = [int]$token
                if ($n -ge 1 -and $n -le $Apps.Count) {
                    $SelectedIndices += ($n - 1)
                }
            }
        }
    }

    if ($SelectedIndices.Count -eq 0) { throw "No valid selection." }

    # ── Download selected APKs ───────────────────────────────────────────────

    $QueueNames = @()
    $QueuePaths = @()
    $ApkCounter = 0

    foreach ($IDX in $SelectedIndices) {
        $App = $Apps[$IDX]

        if ($App.type -eq "gitrelease") {
            try {
                Write-Host "Fetching latest release from $($App.source)..."
                $Release = (Invoke-WebRequest -Uri "https://api.github.com/repos/$($App.source)/releases/latest" -UseBasicParsing).Content | ConvertFrom-Json
                $Asset = $Release.assets | Where-Object { $_.name -like "*.apk" } | Select-Object -First 1
                if (-not $Asset) { throw "No APK found in latest release of $($App.source)." }
                $ApkPath = Join-Path $TempDir "app_${ApkCounter}.apk"
                $ApkCounter++
                Invoke-Download -Uri $Asset.browser_download_url -OutFile $ApkPath -Label "Downloading $($App.name)"
                $QueueNames += $App.name
                $QueuePaths += $ApkPath
            } catch {
                Write-Host "Warning: Failed to download $($App.name): $_. Skipping." -ForegroundColor Yellow
            }

        } elseif ($App.type -eq "gitcollection") {
            try {
                Write-Host "Fetching APK list from $($App.source)..."
                $Release = (Invoke-WebRequest -Uri "https://api.github.com/repos/$($App.source)/releases/latest" -UseBasicParsing).Content | ConvertFrom-Json
                $Assets = $Release.assets | Where-Object { $_.name -like "*.apk" }
                if ($Assets.Count -eq 0) { throw "No APKs found in latest release of $($App.source)." }

                Write-Host ""
                Write-Host "APKs in $($App.name):"
                for ($i = 0; $i -lt $Assets.Count; $i++) {
                    Write-Host "  $($i + 1)) $($Assets[$i].name)"
                }
                $ApkInput = Read-Host "Select APKs to download (e.g. 1 2 3 or 'all')"

                $AssetIndices = @()
                if ($ApkInput.Trim() -eq "all") {
                    $AssetIndices = 0..($Assets.Count - 1)
                } else {
                    foreach ($token in ($ApkInput -split '[,\s]+')) {
                        if ($token -match '^\d+$') {
                            $n = [int]$token
                            if ($n -ge 1 -and $n -le $Assets.Count) { $AssetIndices += ($n - 1) }
                        }
                    }
                }

                foreach ($AIDX in $AssetIndices) {
                    try {
                        $ApkPath = Join-Path $TempDir "app_${ApkCounter}.apk"
                        $ApkCounter++
                        Invoke-Download -Uri $Assets[$AIDX].browser_download_url -OutFile $ApkPath -Label "Downloading $($Assets[$AIDX].name)"
                        $QueueNames += $Assets[$AIDX].name
                        $QueuePaths += $ApkPath
                    } catch {
                        Write-Host "Warning: Failed to download $($Assets[$AIDX].name): $_. Skipping." -ForegroundColor Yellow
                    }
                }
            } catch {
                Write-Host "Warning: Failed to process $($App.name): $_. Skipping." -ForegroundColor Yellow
            }

        } elseif ($App.type -eq "directdownload") {
            try {
                $ApkPath = Join-Path $TempDir "app_${ApkCounter}.apk"
                $ApkCounter++
                Invoke-Download -Uri $App.source -OutFile $ApkPath -Label "Downloading $($App.name)"
                $QueueNames += $App.name
                $QueuePaths += $ApkPath
            } catch {
                Write-Host "Warning: Failed to download $($App.name): $_. Skipping." -ForegroundColor Yellow
            }

        } else {
            Write-Host "Warning: Unknown type '$($App.type)' for '$($App.name)', skipping." -ForegroundColor Yellow
        }
    }

    if ($QueueNames.Count -eq 0) { throw "No apps were successfully downloaded." }

    # ── ADB setup ────────────────────────────────────────────────────────────

    if (Get-Command adb -ErrorAction SilentlyContinue) {
        $AdbCmd = "adb"
    } else {
        Write-Host "adb not found. Downloading platform-tools..."
        $ZipPath = Join-Path $TempDir "platform-tools.zip"
        Invoke-Download -Uri "https://dl.google.com/android/repository/platform-tools-latest-windows.zip" -OutFile $ZipPath -Label "Downloading platform-tools"
        Expand-Archive -Path $ZipPath -DestinationPath $TempDir
        $AdbCmd = Join-Path $TempDir "platform-tools\adb.exe"
        Write-Host "adb downloaded to temporary folder (will be deleted on exit)."
    }

    # ── Connect to device ─────────────────────────────────────────────────────

    $DeviceIp = Read-Host "Enter device IP address"
    Write-Host "Connecting to $DeviceIp..."
    & $AdbCmd connect $DeviceIp
    if ($LASTEXITCODE -ne 0) { throw "Failed to connect to $DeviceIp." }

    Write-Host ""
    Write-Host "Packages on ${DeviceIp}:"
    & $AdbCmd -s $DeviceIp shell pm list packages

    # ── Confirm and install ───────────────────────────────────────────────────

    Write-Host ""
    Write-Host "Ready to install $($QueueNames.Count) app(s) on ${DeviceIp}:"
    foreach ($name in $QueueNames) { Write-Host "  - $name" }
    Write-Host ""
    $Confirm = Read-Host "Proceed with installation? (y/n)"
    if ($Confirm -notmatch '^[Yy]$') {
        Write-Host "Installation cancelled."
        exit 0
    }

    for ($i = 0; $i -lt $QueuePaths.Count; $i++) {
        Write-Host ""
        Write-Host "Installing $($QueueNames[$i])..."
        & $AdbCmd -s $DeviceIp install $QueuePaths[$i]
    }

    $_Completed = $true

} finally {
    if (-not $_Completed) {
        Write-Host ""
        Write-Host "Cancelled, cleaning up..." -ForegroundColor DarkGray
    }
    Invoke-Cleanup
}
