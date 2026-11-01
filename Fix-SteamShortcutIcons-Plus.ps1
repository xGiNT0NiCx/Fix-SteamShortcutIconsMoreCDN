# Steam desktop shortcut icon fixer - extended version
# Based on https://github.com/RNZ01/Fix-SteamShortcutIcons (MIT License)
#
# Changes compared to the original:
#   - tries several Steam CDN hosts and paths instead of only one
#   - checks that the downloaded file really is an .ico
#   - fallback: if no CDN has the icon, the shortcut uses the icon from the game's own .exe
#     (install folder is read from Steam's libraryfolders.vdf / appmanifest, so any drive works)
#   - no ReadKey crash in PowerShell ISE, fixed "Program Files (x86)" fallback path
#
# Run with: powershell -ExecutionPolicy Bypass -File .\Fix-SteamShortcutIcons-Plus.ps1

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

# {0} = AppId, {1} = icon hash. Tried from top to bottom, the first valid .ico wins.
$CdnTemplates = @(
    'https://cdn.cloudflare.steamstatic.com/steamcommunity/public/images/apps/{0}/{1}.ico'
    'https://shared.fastly.steamstatic.com/community_assets/images/apps/{0}/{1}.ico'
    'https://shared.akamai.steamstatic.com/community_assets/images/apps/{0}/{1}.ico'
    'https://shared.cloudflare.steamstatic.com/community_assets/images/apps/{0}/{1}.ico'
    'https://cdn.akamai.steamstatic.com/steamcommunity/public/images/apps/{0}/{1}.ico'
    'https://cdn.fastly.steamstatic.com/steamcommunity/public/images/apps/{0}/{1}.ico'
    'https://steamcdn-a.akamaihd.net/steamcommunity/public/images/apps/{0}/{1}.ico'
)

# .exe files and folders that are never the game itself (anti-cheat, installers, crash handlers ...)
$ExeIgnore = '(?i)crash|unins|setup|install|redist|prereq|dxsetup|directx|dotnet|anticheat|battleye|beservice|gameguard|cefprocess|webhelper|errorreport|bugreport|touchup|cleanup'
$DirIgnore = '(?i)[\\/](__installer|_commonredist|commonredist|redist|redistributables|directx|vcredist|prereqs?)[\\/]'

$Desktops = @(
    [Environment]::GetFolderPath('Desktop'),
    [Environment]::GetFolderPath('CommonDesktopDirectory')
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique

function Write-Banner {
    Clear-Host
    Write-Host ''
    Write-Host '  +--------------------------------------------+' -ForegroundColor DarkCyan
    Write-Host '  |      Steam Shortcut Icon Rescue  (Plus)    |' -ForegroundColor Cyan
    Write-Host '  |   more CDNs + game .exe fallback           |' -ForegroundColor DarkCyan
    Write-Host '  +--------------------------------------------+' -ForegroundColor DarkCyan
    Write-Host ''
}

function Write-Log($Message, $Color = 'Gray', $Icon = '-') {
    Write-Host "  [$Icon] $Message" -ForegroundColor $Color
}

function Wait-ForKey {
    Write-Host ''
    if ($Host.Name -eq 'ConsoleHost') {
        try {
            Write-Host '  Press any key to exit...' -ForegroundColor DarkGray
            [void][Console]::ReadKey($true)
            return
        } catch {}
    }
    [void](Read-Host '  Press Enter to exit')
}

function Get-SteamPath {
    Write-Log 'Looking for Steam...' DarkGray '?'
    foreach ($path in @(
        'HKCU:\Software\Valve\Steam',
        'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam',
        'HKLM:\SOFTWARE\Valve\Steam'
    )) {
        try {
            $item = Get-ItemProperty $path -ErrorAction Stop
            $steamPath = if ($item.SteamPath) { $item.SteamPath } else { $item.InstallPath }
            if ($steamPath -and (Test-Path $steamPath)) {
                Write-Log "Steam found via registry: $steamPath" Green 'OK'
                return $steamPath
            }
        } catch {}
    }

    foreach ($path in @("${env:ProgramFiles(x86)}\Steam", "$env:ProgramFiles\Steam")) {
        if ($path -and (Test-Path $path)) {
            Write-Log "Steam found via common path: $path" Green 'OK'
            return $path
        }
    }

    throw 'Steam folder not found. Is Steam installed for this Windows user?'
}

function Get-SteamLibraries {
    $libs = @($Steam)
    $vdf = Join-Path $Steam 'steamapps\libraryfolders.vdf'
    if (Test-Path $vdf) {
        foreach ($line in Get-Content $vdf) {
            if ($line -match '^\s*"path"\s+"(.+)"\s*$') { $libs += ($Matches[1] -replace '\\\\', '\') }
        }
    }
    $libs | Where-Object { $_ -and (Test-Path $_) } |
        ForEach-Object { (Resolve-Path $_).ProviderPath.TrimEnd('\', '/') } |
        Sort-Object -Unique
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
            IconExists = [bool]($icon -and (Test-Path $icon))
        }
    }
}

function Get-ShortError($err) {
    $code = 0
    try { $code = [int]$err.Exception.Response.StatusCode } catch {}
    if ($code) { "HTTP $code" } else { $err.Exception.Message }
}

function Test-IcoFile($Path) {
    if (!(Test-Path $Path)) { return $false }
    $b = [IO.File]::ReadAllBytes($Path)
    # .ico header: 00 00 01 00
    return ($b.Length -ge 100 -and $b[0] -eq 0 -and $b[1] -eq 0 -and $b[2] -eq 1 -and $b[3] -eq 0)
}

function Get-IconFromCdn($AppId, $Hash, $Target) {
    $tmp = "$Target.part"
    foreach ($tpl in $CdnTemplates) {
        $url = $tpl -f $AppId, $Hash
        $cdnHost = ([uri]$url).Host
        try {
            Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing -TimeoutSec 20
            if (Test-IcoFile $tmp) {
                Move-Item $tmp $Target -Force
                Write-Log "Found on $cdnHost" Green 'OK'
                return $true
            }
            Write-Log "${cdnHost}: answer is not a valid .ico" DarkGray '~'
        } catch {
            Write-Log "${cdnHost}: $(Get-ShortError $_)" DarkGray '~'
        }
    }
    Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    return $false
}

function Find-GameExe($AppId) {
    foreach ($lib in $Libraries) {
        $acf = Join-Path $lib "steamapps\appmanifest_$AppId.acf"
        if (!(Test-Path $acf)) { continue }

        $installDir = $null
        foreach ($line in Get-Content $acf) {
            if ($line -match '^\s*"installdir"\s+"(.+)"\s*$') { $installDir = $Matches[1]; break }
        }
        if (!$installDir) { continue }

        $gameDir = Join-Path $lib "steamapps\common\$installDir"
        if (!(Test-Path $gameDir)) { continue }
        Write-Log "Game folder: $gameDir" DarkGray 'DIR'

        # The biggest .exe that isn't a launcher/anti-cheat/installer is almost always the game itself
        $exe = Get-ChildItem $gameDir -Filter *.exe -Recurse -Depth 3 -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -notmatch $ExeIgnore -and $_.FullName -notmatch $DirIgnore } |
            Sort-Object Length -Descending |
            Select-Object -First 1
        if ($exe) { return $exe.FullName }
    }
    return $null
}

function Set-ShortcutIcon($Path, $IconPath) {
    if ($IconPath -match '[^\x20-\x7E]') { throw "Icon path contains special characters, can't write it safely: $IconPath" }

    # Drop old IconFile/IconIndex lines, write fresh ones right below the URL= line
    $out = [System.Collections.Generic.List[string]]::new()
    $inserted = $false
    foreach ($line in Get-Content $Path) {
        if ($line -like 'IconFile=*' -or $line -like 'IconIndex=*') { continue }
        $out.Add($line)
        if (!$inserted -and $line -like 'URL=*') {
            $out.Add('IconIndex=0')
            $out.Add("IconFile=$IconPath")
            $inserted = $true
        }
    }
    if (!$inserted) { $out.Add('IconIndex=0'); $out.Add("IconFile=$IconPath") }
    Set-Content -Path $Path -Value $out -Encoding ASCII
}

function Repair-Shortcut($s) {
    if ($s.AppId -notmatch '^\d+$') { throw "Unexpected AppId '$($s.AppId)'" }

    $icon = $null
    $source = $null
    if ($s.Hash -match '^[a-fA-F0-9]{40}$') {
        Write-Log "Downloading icon for $($s.Name)" Cyan 'GET'
        $target = Join-Path $IconDir "steam_$($s.AppId)_$($s.Hash)_$(Get-Date -Format yyyyMMddHHmmss).ico"
        if (Get-IconFromCdn $s.AppId $s.Hash $target) { $icon = $target; $source = 'CDN' }
    } else {
        Write-Log "$($s.Name): no Steam icon hash in shortcut, skipping CDN" DarkYellow '~'
    }

    if (!$icon) {
        Write-Log "Trying the icon from the game's .exe instead" Yellow 'EXE'
        $exe = Find-GameExe $s.AppId
        if (!$exe) { throw 'No CDN had the icon and the game .exe was not found (game not installed?)' }
        $icon = $exe
        $source = 'EXE'
    }

    Set-ShortcutIcon $s.Path $icon
    Write-Log "Patched shortcut -> $icon" Green 'OK'
    [pscustomobject]@{ Shortcut = $s.Name; AppId = $s.AppId; Source = $source; Icon = $icon }
}

function Refresh-ExplorerIcons {
    Write-Log 'Restarting Explorer and clearing the icon cache...' Yellow 'REFRESH'
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force -ErrorAction SilentlyContinue
    Remove-Item "$env:LOCALAPPDATA\Microsoft\Windows\Explorer\iconcache*" -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
}

# ---------------------------------------------------------------- main

Write-Banner
$Steam = Get-SteamPath
$IconDir = Join-Path $Steam 'steam\games'
New-Item -ItemType Directory -Force $IconDir | Out-Null
$Libraries = @(Get-SteamLibraries)

Write-Log "Scanning: $($Desktops -join '; ')" DarkGray '?'
Write-Log "Steam libraries: $($Libraries -join '; ')" DarkGray '?'
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
$missing | Select-Object Name, AppId, IconFile | Format-Table -AutoSize | Out-Host

Write-Host '  Plan:' -ForegroundColor Yellow
Write-Log "Download the original .ico from Steam's CDN (tries $($CdnTemplates.Count) addresses)" Gray '1'
Write-Log "If no CDN has it: use the icon from the game's own .exe" Gray '2'
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
    Write-Host ''
}

if ($fixed) {
    Write-Host '  Fixed:' -ForegroundColor Green
    $fixed | Select-Object Shortcut, AppId, Source, Icon | Format-Table -AutoSize | Out-Host
}
if ($failed) {
    Write-Host '  Failed:' -ForegroundColor Red
    $failed | Format-Table -AutoSize | Out-Host
}

if ($fixed) { Refresh-ExplorerIcons }
Write-Host ''
Write-Log "Done. Fixed $($fixed.Count), failed $($failed.Count)." Green 'OK'
Wait-ForKey
