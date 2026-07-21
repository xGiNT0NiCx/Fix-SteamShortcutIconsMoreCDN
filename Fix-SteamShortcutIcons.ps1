# Steam desktop shortcut icon fixer
# Run with: powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\Desktop\Fix-SteamShortcutIcons.ps1"

$ErrorActionPreference = 'Stop'
$Desktops = @(
    [Environment]::GetFolderPath('Desktop'),
    [Environment]::GetFolderPath('CommonDesktopDirectory')
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

function Write-Banner {
    Clear-Host
    Write-Host ''
    Write-Host '  +--------------------------------------------+' -ForegroundColor DarkCyan
    Write-Host '  |        Steam Shortcut Icon Rescue          |' -ForegroundColor Cyan
    Write-Host '  |        missing .ico files? bonk.           |' -ForegroundColor DarkCyan
    Write-Host '  +--------------------------------------------+' -ForegroundColor DarkCyan
    Write-Host ''
}

function Write-Log($Message, $Color = 'Gray', $Icon = '-') {
    Write-Host "  [$Icon] $Message" -ForegroundColor $Color
}

function Wait-ForKey {
    Write-Host '  Press any key to exit...' -ForegroundColor DarkGray
    [void][System.Console]::ReadKey($true)
}

function Get-SteamPath {
    Write-Log 'Looking for Steam...' DarkGray '?' 
    $registryPaths = @(
        'HKCU:\Software\Valve\Steam',
        'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam',
        'HKLM:\SOFTWARE\Valve\Steam'
    )

    foreach ($path in $registryPaths) {
        try {
            $steamPath = (Get-ItemProperty $path -ErrorAction Stop).SteamPath
            if ($steamPath -and (Test-Path $steamPath)) {
                Write-Log "Steam found via registry: $steamPath" Green 'OK'
                return $steamPath
            }
        } catch {}
    }

    foreach ($path in @(
        "$env:ProgramFiles(x86)\Steam",
        "$env:ProgramFiles\Steam"
    )) {
        if ($path -and (Test-Path $path)) {
            Write-Log "Steam found via common path: $path" Green 'OK'
            return $path
        }
    }

    throw 'Steam folder not found. Is Steam installed for this Windows user?'
}

function Get-SteamShortcut {
    Get-ChildItem $Desktops -Filter *.url | ForEach-Object {
        $lines = Get-Content $_.FullName
        $url = $lines | Where-Object { $_ -like 'URL=steam://rungameid/*' } | Select-Object -First 1
        if (!$url) { return }

        $iconLine = $lines | Where-Object { $_ -like 'IconFile=*' } | Select-Object -First 1
        $appid = $url -replace '.*/', ''
        $icon = if ($iconLine) { $iconLine -replace '^IconFile=', '' } else { '' }
        $hash = [IO.Path]::GetFileNameWithoutExtension($icon) -replace "^steam_$appid`_", '' -replace '_\d{14}$', '' -replace '_orig$', ''

        [pscustomobject]@{
            Name       = $_.Name
            Path       = $_.FullName
            AppId      = $appid
            IconFile   = $icon
            Hash       = $hash
            IconExists = $icon -and (Test-Path $icon)
        }
    }
}

function Repair-Shortcut($s) {
    if ($s.Hash -notmatch '^[a-fA-F0-9]{40}$') { throw "No Steam icon hash in $($s.Name)" }

    $newIcon = Join-Path $IconDir "steam_$($s.AppId)_$($s.Hash)_$(Get-Date -Format yyyyMMddHHmmss).ico"
    $url = "https://cdn.cloudflare.steamstatic.com/steamcommunity/public/images/apps/$($s.AppId)/$($s.Hash).ico"

    Write-Log "Downloading $($s.Name)" Cyan 'GET'
    Invoke-WebRequest -Uri $url -OutFile $newIcon -UseBasicParsing -TimeoutSec 25
    if ((Get-Item $newIcon).Length -lt 100) { throw 'Downloaded file is too small' }

    $lines = Get-Content $s.Path
    if ($lines -match '^IconFile=') {
        $lines = $lines | ForEach-Object {
            if ($_ -like 'IconFile=*') { "IconFile=$newIcon" }
            elseif ($_ -like 'IconIndex=*') { 'IconIndex=0' }
            else { $_ }
        }
    } else {
        $lines += 'IconIndex=0'
        $lines += "IconFile=$newIcon"
    }

    Set-Content -Path $s.Path -Value $lines -Encoding ASCII
    Write-Log "Patched shortcut -> $([IO.Path]::GetFileName($newIcon))" Green 'OK'
    [pscustomobject]@{ Shortcut = $s.Name; AppId = $s.AppId; Icon = $newIcon }
}

function Refresh-ExplorerIcons {
    Write-Log 'Restarting Explorer and poking the icon cache...' Yellow 'REFRESH'
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache*" -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
}

Write-Banner
$Steam = Get-SteamPath
$IconDir = Join-Path $Steam 'steam\games'
New-Item -ItemType Directory -Force $IconDir | Out-Null

Write-Log "Scanning: $($Desktops -join '; ')" DarkGray '?' 
$items = @(Get-SteamShortcut)
$missing = @($items | Where-Object { !$_.IconExists })

Write-Host ''
Write-Log "Steam shortcuts found: $($items.Count)" Cyan 'GAME'
Write-Log "Missing icon files:   $($missing.Count)" $(if ($missing) { 'Yellow' } else { 'Green' }) $(if ($missing) { '!' } else { 'OK' })
Write-Log "Icon folder:          $IconDir" DarkGray 'DIR'

if (!$missing) {
    Write-Host ''
    Write-Log 'All good. No broken Steam shortcut icons found.' Green 'OK'
    Wait-ForKey
    exit
}

Write-Host ''
Write-Host '  Shortcuts queued for repair:' -ForegroundColor Yellow
$missing | Select-Object Name, AppId, IconFile | Format-Table -AutoSize

Write-Host '  Plan:' -ForegroundColor Yellow
Write-Log 'Download original .ico files from Steam CDN' Gray '1'
Write-Log 'Save them into Steam\steam\games' Gray '2'
Write-Log 'Update each .url IconFile line' Gray '3'
Write-Log 'Clear Windows icon cache and restart Explorer' Gray '4'

$confirm = Read-Host "`n  Type Y to launch the rescue mission"
if ($confirm -notin @('y', 'Y')) {
    Write-Host ''
    Write-Log 'Cancelled. Nothing changed.' DarkYellow 'X'
    Wait-ForKey
    exit
}

Write-Host ''
$fixed = @()
$failed = @()
foreach ($s in $missing) {
    try { $fixed += Repair-Shortcut $s }
    catch {
        Write-Log "$($s.Name): $($_.Exception.Message)" Red 'X'
        $failed += [pscustomobject]@{ Shortcut = $s.Name; Error = $_.Exception.Message }
    }
}

Write-Host ''
if ($fixed) {
    Write-Host '  Fixed:' -ForegroundColor Green
    $fixed | Select-Object Shortcut, AppId, Icon | Format-Table -AutoSize
}
if ($failed) {
    Write-Host '  Failed:' -ForegroundColor Red
    $failed | Format-Table -AutoSize
}

if ($fixed) { Refresh-ExplorerIcons }
Write-Host ''
Write-Log "Done. Fixed $($fixed.Count), failed $($failed.Count)." Green 'OK'
Wait-ForKey
