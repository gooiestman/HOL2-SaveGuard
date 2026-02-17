<#
.SYNOPSIS
    HOL2 SaveGuard - Automatic Save Backup Tool for High On Life 2
.DESCRIPTION
    Monitors and backs up High On Life 2 save files on a timer to protect
    against softlocks, corruption, and lost progress.
    
    Free tool - share freely. No warranty implied.
.VERSION
    1.0.0
.LICENSE
    MIT License - Free to use, modify, and distribute.
#>

# ============================================================
#  CONFIGURATION
# ============================================================

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path $ScriptDir "config.ini"

# Defaults (overridden by config.ini if it exists)
$Config = @{
    BackupRoot       = Join-Path $ScriptDir "Backups"
    IntervalMinutes  = 10
    MaxBackups       = 0          # 0 = unlimited
    MaxAgeDays       = 0          # 0 = keep forever
    IncludeProfile   = $true
    SaveSlot         = "All"      # "All", "Slot1", "Slot2", "Slot3"
    MaxCopyAttempts  = 10
    RetryDelayMs     = 300
    ShowNotifications = $true
}

# Auto-detect save folder
$DefaultSaveDir = Join-Path $env:LOCALAPPDATA "HighOnLife2\Saved\SaveGames"

# ============================================================
#  CONFIG FILE HANDLING
# ============================================================

function Save-Config {
    $lines = @(
        "# HOL2 SaveGuard Configuration"
        "# Edit these values or use the in-app Settings menu."
        ""
        "BackupRoot=$($Config.BackupRoot)"
        "IntervalMinutes=$($Config.IntervalMinutes)"
        "MaxBackups=$($Config.MaxBackups)"
        "MaxAgeDays=$($Config.MaxAgeDays)"
        "IncludeProfile=$($Config.IncludeProfile)"
        "SaveSlot=$($Config.SaveSlot)"
        "MaxCopyAttempts=$($Config.MaxCopyAttempts)"
        "RetryDelayMs=$($Config.RetryDelayMs)"
        "ShowNotifications=$($Config.ShowNotifications)"
    )
    $lines | Set-Content $ConfigFile -Encoding UTF8
}

function Load-Config {
    if (!(Test-Path $ConfigFile)) {
        Save-Config
        return
    }
    $raw = Get-Content $ConfigFile -Encoding UTF8
    foreach ($line in $raw) {
        $line = $line.Trim()
        if ($line -eq "" -or $line.StartsWith("#")) { continue }
        $parts = $line -split "=", 2
        if ($parts.Count -ne 2) { continue }
        $key = $parts[0].Trim()
        $val = $parts[1].Trim()
        switch ($key) {
            "BackupRoot"        { $Config.BackupRoot = $val }
            "IntervalMinutes"   { $Config.IntervalMinutes = [int]$val }
            "MaxBackups"        { $Config.MaxBackups = [int]$val }
            "MaxAgeDays"        { $Config.MaxAgeDays = [int]$val }
            "IncludeProfile"    { $Config.IncludeProfile = ($val -eq "True") }
            "SaveSlot"          { $Config.SaveSlot = $val }
            "MaxCopyAttempts"   { $Config.MaxCopyAttempts = [int]$val }
            "RetryDelayMs"      { $Config.RetryDelayMs = [int]$val }
            "ShowNotifications" { $Config.ShowNotifications = ($val -eq "True") }
        }
    }
}

# ============================================================
#  UTILITY FUNCTIONS
# ============================================================

function Write-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  =============================================" -ForegroundColor Cyan
    Write-Host "   HOL2 SaveGuard v1.0" -ForegroundColor White
    Write-Host "   Automatic Save Backup for High On Life 2" -ForegroundColor Gray
    Write-Host "  =============================================" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Status($msg, $color = "White") {
    $ts = (Get-Date).ToString("HH:mm:ss")
    Write-Host "  [$ts] " -ForegroundColor DarkGray -NoNewline
    Write-Host $msg -ForegroundColor $color
}

function Write-Info($msg) { Write-Status $msg "Cyan" }
function Write-Ok($msg)   { Write-Status $msg "Green" }
function Write-Warn($msg) { Write-Status $msg "Yellow" }
function Write-Err($msg)  { Write-Status $msg "Red" }

function Timestamp { (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss") }

function Format-Size($bytes) {
    if ($bytes -lt 1KB) { return "$bytes B" }
    if ($bytes -lt 1MB) { return "{0:N1} KB" -f ($bytes / 1KB) }
    return "{0:N1} MB" -f ($bytes / 1MB)
}

function Get-FileSig($path) {
    if (!(Test-Path $path)) { return $null }
    $item = Get-Item $path
    return "$($item.LastWriteTimeUtc.Ticks)-$($item.Length)"
}

function TryCopy($src, $dst) {
    for ($i = 1; $i -le $Config.MaxCopyAttempts; $i++) {
        try {
            if (!(Test-Path $src)) { return $false }
            $fs = [System.IO.File]::Open($src, 'Open', 'Read', 'ReadWrite')
            $fs.Close()
            Copy-Item -Force $src $dst -ErrorAction Stop
            return $true
        } catch {
            if ($i -lt $Config.MaxCopyAttempts) {
                Start-Sleep -Milliseconds $Config.RetryDelayMs
            }
        }
    }
    return $false
}

function Get-SaveDir {
    # Auto-detect: check default location
    if (Test-Path $DefaultSaveDir) {
        return $DefaultSaveDir
    }
    # Fallback: search common locations
    $searchPaths = @(
        "$env:LOCALAPPDATA\HighOnLife2\Saved\SaveGames",
        "$env:APPDATA\HighOnLife2\Saved\SaveGames"
    )
    foreach ($p in $searchPaths) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Get-TargetFiles {
    $files = @()
    $slots = @()
    
    if ($Config.SaveSlot -eq "All") {
        $slots = @("Slot0", "Slot1", "Slot2")
    } else {
        $slots = @($Config.SaveSlot)
    }
    
    foreach ($slot in $slots) {
        $files += "$slot.sav"
        $files += "${slot}_Swap.sav"
    }
    
    if ($Config.IncludeProfile) {
        $files += "Profile.sav"
    }
    
    return $files
}

# ============================================================
#  BACKUP ENGINE
# ============================================================

function Invoke-Backup {
    param(
        [string]$SaveDir,
        [string[]]$Files,
        [string]$Reason = "manual"
    )
    
    $snap = Join-Path $Config.BackupRoot (Timestamp)
    New-Item -ItemType Directory -Force -Path $snap | Out-Null
    
    $logFile = Join-Path $Config.BackupRoot "backup_log.txt"
    $results = @()
    $anySuccess = $false
    
    foreach ($f in $Files) {
        $src = Join-Path $SaveDir $f
        if (!(Test-Path $src)) { continue }
        
        $dst = Join-Path $snap $f
        $ok = TryCopy $src $dst
        
        if ($ok) {
            $info = Get-Item $dst
            $sizeStr = Format-Size $info.Length
            $results += "  OK    $f  ($sizeStr)"
            $logEntry = "{0}  OK    {1}  {2}  {3}" -f (Get-Date), $f, $info.Length, $Reason
            $logEntry | Out-File $logFile -Append -Encoding UTF8
            $anySuccess = $true
        } else {
            $results += "  FAIL  $f"
            $logEntry = "{0}  FAIL  {1}  -  {2}" -f (Get-Date), $f, $Reason
            $logEntry | Out-File $logFile -Append -Encoding UTF8
        }
    }
    
    # Write manifest
    $manifest = @(
        "HOL2 SaveGuard Backup"
        "Created: $(Get-Date)"
        "Reason: $Reason"
        "Source: $SaveDir"
        ""
        "Files:"
    ) + $results
    $manifest | Set-Content (Join-Path $snap "manifest.txt") -Encoding UTF8
    
    return @{ Success = $anySuccess; Path = $snap; Results = $results }
}

function Invoke-Cleanup {
    if ($Config.MaxBackups -eq 0 -and $Config.MaxAgeDays -eq 0) { return 0 }
    
    $backupDirs = Get-ChildItem $Config.BackupRoot -Directory |
        Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}$' } |
        Sort-Object Name
    
    $removed = 0
    
    # Remove by age
    if ($Config.MaxAgeDays -gt 0) {
        $cutoff = (Get-Date).AddDays(-$Config.MaxAgeDays)
        foreach ($d in $backupDirs) {
            if ($d.CreationTime -lt $cutoff) {
                Remove-Item $d.FullName -Recurse -Force -ErrorAction SilentlyContinue
                $removed++
            }
        }
        # Refresh list
        $backupDirs = Get-ChildItem $Config.BackupRoot -Directory |
            Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}$' } |
            Sort-Object Name
    }
    
    # Remove by count (keep newest)
    if ($Config.MaxBackups -gt 0 -and $backupDirs.Count -gt $Config.MaxBackups) {
        $toRemove = $backupDirs.Count - $Config.MaxBackups
        $oldest = $backupDirs | Select-Object -First $toRemove
        foreach ($d in $oldest) {
            Remove-Item $d.FullName -Recurse -Force -ErrorAction SilentlyContinue
            $removed++
        }
    }
    
    return $removed
}

# ============================================================
#  RESTORE FUNCTION
# ============================================================

function Show-RestoreMenu {
    param([string]$SaveDir)
    
    $backupDirs = Get-ChildItem $Config.BackupRoot -Directory |
        Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}$' } |
        Sort-Object Name -Descending
    
    if ($backupDirs.Count -eq 0) {
        Write-Warn "No backups found."
        Write-Host ""
        Read-Host "  Press Enter to return"
        return
    }
    
    Write-Header
    Write-Host "  RESTORE FROM BACKUP" -ForegroundColor Yellow
    Write-Host "  -------------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  ** CLOSE HIGH ON LIFE 2 BEFORE RESTORING **" -ForegroundColor Red
    Write-Host ""
    
    # Show last 20
    $showing = [Math]::Min($backupDirs.Count, 20)
    Write-Host "  Showing $showing most recent backups ($($backupDirs.Count) total):" -ForegroundColor Gray
    Write-Host ""
    
    for ($i = 0; $i -lt $showing; $i++) {
        $d = $backupDirs[$i]
        $fileCount = (Get-ChildItem $d.FullName -File -Filter "*.sav" -ErrorAction SilentlyContinue).Count
        $totalSize = (Get-ChildItem $d.FullName -File -Filter "*.sav" -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $sizeStr = if ($totalSize) { Format-Size $totalSize } else { "empty" }
        
        $num = $i + 1
        $dateStr = $d.Name -replace "_", " @ " -replace "-(\d{2}) @ (\d{2})", '-$1  $2:'
        
        # Parse the folder name back into a readable date
        try {
            $parsed = [DateTime]::ParseExact($d.Name, "yyyy-MM-dd_HH-mm-ss", $null)
            $dateStr = $parsed.ToString("MMM dd, yyyy  hh:mm:ss tt")
        } catch {
            $dateStr = $d.Name
        }
        
        $numStr = if ($num -lt 10) { " $num" } else { "$num" }
        Write-Host "  [$numStr]  $dateStr   ($fileCount files, $sizeStr)" -ForegroundColor White
    }
    
    Write-Host ""
    Write-Host "   [0]  Cancel" -ForegroundColor DarkGray
    Write-Host ""
    
    $choice = Read-Host "  Enter number to restore"
    
    if ($choice -eq "0" -or $choice -eq "") { return }
    
    $idx = 0
    if (-not [int]::TryParse($choice, [ref]$idx)) { return }
    if ($idx -lt 1 -or $idx -gt $showing) { return }
    
    $selected = $backupDirs[$idx - 1]
    $savFiles = Get-ChildItem $selected.FullName -File -Filter "*.sav"
    
    Write-Host ""
    Write-Host "  You are about to OVERWRITE your current saves with:" -ForegroundColor Yellow
    Write-Host "  Backup: $($selected.Name)" -ForegroundColor White
    foreach ($sf in $savFiles) {
        Write-Host "    - $($sf.Name)  ($(Format-Size $sf.Length))" -ForegroundColor Gray
    }
    Write-Host ""
    Write-Host "  Your current saves will be backed up first (safety net)." -ForegroundColor Cyan
    Write-Host ""
    
    $confirm = Read-Host "  Type YES to confirm restore"
    if ($confirm -ne "YES") {
        Write-Warn "Restore cancelled."
        Start-Sleep -Seconds 1
        return
    }
    
    # Safety backup of current saves before restoring
    Write-Info "Creating safety backup of current saves..."
    $safetyResult = Invoke-Backup -SaveDir $SaveDir -Files (Get-TargetFiles) -Reason "pre-restore-safety"
    if ($safetyResult.Success) {
        Write-Ok "Safety backup created: $($safetyResult.Path)"
    }
    
    # Restore
    $restored = 0
    $failed = 0
    foreach ($sf in $savFiles) {
        $dst = Join-Path $SaveDir $sf.Name
        try {
            Copy-Item -Force $sf.FullName $dst -ErrorAction Stop
            Write-Ok "Restored: $($sf.Name)"
            $restored++
        } catch {
            Write-Err "Failed to restore: $($sf.Name) - $($_.Exception.Message)"
            $failed++
        }
    }
    
    Write-Host ""
    if ($failed -eq 0) {
        Write-Ok "Restore complete! $restored file(s) restored."
    } else {
        Write-Warn "Restore finished with $failed error(s). $restored file(s) restored."
    }
    
    # Log it
    $logFile = Join-Path $Config.BackupRoot "backup_log.txt"
    "{0}  RESTORE  from {1}  restored={2} failed={3}" -f (Get-Date), $selected.Name, $restored, $failed |
        Out-File $logFile -Append -Encoding UTF8
    
    Write-Host ""
    Read-Host "  Press Enter to return"
}

# ============================================================
#  SETTINGS MENU
# ============================================================

function Show-SettingsMenu {
    while ($true) {
        Write-Header
        Write-Host "  SETTINGS" -ForegroundColor Yellow
        Write-Host "  --------" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  [1]  Backup interval:    $($Config.IntervalMinutes) minutes" -ForegroundColor White
        Write-Host "  [2]  Save slot:          $($Config.SaveSlot)" -ForegroundColor White
        Write-Host "  [3]  Include Profile:    $($Config.IncludeProfile)" -ForegroundColor White
        Write-Host "  [4]  Max backups:        $(if($Config.MaxBackups -eq 0){'Unlimited'}else{$Config.MaxBackups})" -ForegroundColor White
        Write-Host "  [5]  Max age (days):     $(if($Config.MaxAgeDays -eq 0){'Forever'}else{"$($Config.MaxAgeDays) days"})" -ForegroundColor White
        Write-Host "  [6]  Backup folder:      $($Config.BackupRoot)" -ForegroundColor White
        Write-Host ""
        Write-Host "  [S]  Save settings" -ForegroundColor Green
        Write-Host "  [0]  Back to main menu" -ForegroundColor DarkGray
        Write-Host ""
        
        $choice = Read-Host "  Choose option"
        
        switch ($choice) {
            "1" {
                $val = Read-Host "  Enter interval in minutes (1-60)"
                $parsed = 0
                if ([int]::TryParse($val, [ref]$parsed) -and $parsed -ge 1 -and $parsed -le 60) {
                    $Config.IntervalMinutes = $parsed
                    Write-Ok "Interval set to $parsed minutes."
                } else { Write-Err "Invalid value." }
                Start-Sleep -Seconds 1
            }
            "2" {
                Write-Host ""
                Write-Host "  [1] All slots  [2] Slot0  [3] Slot1  [4] Slot2" -ForegroundColor Cyan
                $slotChoice = Read-Host "  Choose"
                switch ($slotChoice) {
                    "1" { $Config.SaveSlot = "All" }
                    "2" { $Config.SaveSlot = "Slot0" }
                    "3" { $Config.SaveSlot = "Slot1" }
                    "4" { $Config.SaveSlot = "Slot2" }
                }
                Write-Ok "Save slot set to $($Config.SaveSlot)."
                Start-Sleep -Seconds 1
            }
            "3" {
                $Config.IncludeProfile = -not $Config.IncludeProfile
                Write-Ok "Include Profile: $($Config.IncludeProfile)"
                Start-Sleep -Seconds 1
            }
            "4" {
                $val = Read-Host "  Max backups to keep (0 = unlimited)"
                $parsed = 0
                if ([int]::TryParse($val, [ref]$parsed) -and $parsed -ge 0) {
                    $Config.MaxBackups = $parsed
                } else { Write-Err "Invalid value." }
                Start-Sleep -Seconds 1
            }
            "5" {
                $val = Read-Host "  Max age in days (0 = keep forever)"
                $parsed = 0
                if ([int]::TryParse($val, [ref]$parsed) -and $parsed -ge 0) {
                    $Config.MaxAgeDays = $parsed
                } else { Write-Err "Invalid value." }
                Start-Sleep -Seconds 1
            }
            "6" {
                $val = Read-Host "  Enter new backup folder path"
                if ($val -ne "") {
                    $Config.BackupRoot = $val
                    Write-Ok "Backup folder set to: $val"
                }
                Start-Sleep -Seconds 1
            }
            "S" {
                Save-Config
                Write-Ok "Settings saved to config.ini"
                Start-Sleep -Seconds 1
            }
            "s" {
                Save-Config
                Write-Ok "Settings saved to config.ini"
                Start-Sleep -Seconds 1
            }
            "0" { return }
            default { }
        }
    }
}

# ============================================================
#  MONITORING LOOP
# ============================================================

function Start-Monitoring {
    param([string]$SaveDir)
    
    $files = Get-TargetFiles
    $logFile = Join-Path $Config.BackupRoot "backup_log.txt"
    
    New-Item -ItemType Directory -Force -Path $Config.BackupRoot | Out-Null
    
    # Initialize signatures
    $lastSigs = @{}
    foreach ($f in $files) {
        $lastSigs[$f] = Get-FileSig (Join-Path $SaveDir $f)
    }
    
    # Log start
    "$(Get-Date)  MONITOR STARTED  Slot=$($Config.SaveSlot)  Interval=$($Config.IntervalMinutes)min  Files=$($files -join ', ')" |
        Out-File $logFile -Append -Encoding UTF8
    
    Write-Header
    Write-Host "  MONITORING ACTIVE" -ForegroundColor Green
    Write-Host "  -----------------" -ForegroundColor DarkGray
    Write-Host ""
    Write-Info "Source:   $SaveDir"
    Write-Info "Backups:  $($Config.BackupRoot)"
    Write-Info "Slot:     $($Config.SaveSlot)"
    Write-Info "Interval: $($Config.IntervalMinutes) minutes"
    Write-Info "Watching: $($files -join ', ')"
    Write-Host ""
    Write-Host "  Press Ctrl+C to stop monitoring." -ForegroundColor DarkGray
    Write-Host "  ----------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
    
    $backupCount = 0
    $startTime = Get-Date
    
    while ($true) {
        # Countdown with live display
        $totalSeconds = $Config.IntervalMinutes * 60
        for ($s = $totalSeconds; $s -gt 0; $s--) {
            $mins = [Math]::Floor($s / 60)
            $secs = $s % 60
            $countdown = "{0}:{1:D2}" -f $mins, $secs
            Write-Host "`r  Next check in $countdown  |  Backups: $backupCount  |  Running: $((Get-Date) - $startTime | ForEach-Object { '{0:D2}:{1:D2}:{2:D2}' -f $_.Hours, $_.Minutes, $_.Seconds })" -NoNewline -ForegroundColor DarkGray
            Start-Sleep -Seconds 1
        }
        Write-Host "`r                                                                              `r" -NoNewline
        
        # Check for changes
        $changed = $false
        $changedFiles = @()
        $currSigs = @{}
        
        foreach ($f in $files) {
            $p = Join-Path $SaveDir $f
            $sig = Get-FileSig $p
            $currSigs[$f] = $sig
            if ($sig -ne $lastSigs[$f]) {
                $changed = $true
                $changedFiles += $f
            }
        }
        
        if ($changed) {
            Write-Info "Change detected in: $($changedFiles -join ', ')"
            
            $result = Invoke-Backup -SaveDir $SaveDir -Files $files -Reason "auto-timer"
            
            if ($result.Success) {
                $backupCount++
                Write-Ok "Backup #$backupCount saved: $(Split-Path $result.Path -Leaf)"
                foreach ($r in $result.Results) {
                    Write-Host "  $r" -ForegroundColor Gray
                }
            } else {
                Write-Err "Backup failed!"
            }
            
            # Update signatures
            foreach ($f in $files) { $lastSigs[$f] = $currSigs[$f] }
            
            # Run cleanup
            $cleaned = Invoke-Cleanup
            if ($cleaned -gt 0) {
                Write-Info "Cleaned up $cleaned old backup(s)."
            }
        } else {
            Write-Status "No changes detected." "DarkGray"
        }
        
        Write-Host ""
    }
}

# ============================================================
#  MAIN MENU
# ============================================================

function Show-MainMenu {
    Load-Config
    
    $saveDir = Get-SaveDir
    
    while ($true) {
        Write-Header
        
        # Status display
        if ($saveDir) {
            Write-Host "  Save folder: " -NoNewline -ForegroundColor Gray
            Write-Host "FOUND" -ForegroundColor Green
            Write-Host "  $saveDir" -ForegroundColor DarkGray
            
            # Show existing save files
            $existingFiles = Get-ChildItem $saveDir -Filter "*.sav" -ErrorAction SilentlyContinue
            if ($existingFiles) {
                Write-Host "  Found $($existingFiles.Count) save file(s)" -ForegroundColor Gray
            }
        } else {
            Write-Host "  Save folder: " -NoNewline -ForegroundColor Gray
            Write-Host "NOT FOUND" -ForegroundColor Red
            Write-Host "  High On Life 2 may not be installed, or hasn't been run yet." -ForegroundColor DarkGray
        }
        
        # Backup stats
        if (Test-Path $Config.BackupRoot) {
            $backupDirs = Get-ChildItem $Config.BackupRoot -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}$' }
            $backupCount = if ($backupDirs) { $backupDirs.Count } else { 0 }
            Write-Host "  Backups: $backupCount snapshot(s) in $($Config.BackupRoot)" -ForegroundColor Gray
        } else {
            Write-Host "  Backups: None yet" -ForegroundColor Gray
        }
        
        Write-Host ""
        Write-Host "  ===========================================" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  [1]  Start Monitoring" -ForegroundColor Green
        Write-Host "       Auto-backup every $($Config.IntervalMinutes) min when saves change"
        Write-Host ""
        Write-Host "  [2]  Backup Now" -ForegroundColor Cyan
        Write-Host "       Create an immediate snapshot"
        Write-Host ""
        Write-Host "  [3]  Restore a Backup" -ForegroundColor Yellow
        Write-Host "       Recover a previous save"
        Write-Host ""
        Write-Host "  [4]  Settings" -ForegroundColor Magenta
        Write-Host "       Interval, slots, retention, paths"
        Write-Host ""
        Write-Host "  [5]  Open Backup Folder" -ForegroundColor White
        Write-Host ""
        Write-Host "  [6]  Set Save Folder Manually" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  [0]  Exit" -ForegroundColor DarkGray
        Write-Host ""
        
        $choice = Read-Host "  Choose option"
        
        switch ($choice) {
            "1" {
                if (!$saveDir) {
                    Write-Err "Save folder not found. Use option [6] to set it manually."
                    Start-Sleep -Seconds 2
                    continue
                }
                try {
                    Start-Monitoring -SaveDir $saveDir
                } catch {
                    if ($_.Exception.Message -match "OperationStopped|PipelineStopped") {
                        Write-Host ""
                        Write-Warn "Monitoring stopped by user."
                        Start-Sleep -Seconds 1
                    } else {
                        Write-Err "Error: $($_.Exception.Message)"
                        Start-Sleep -Seconds 2
                    }
                }
            }
            "2" {
                if (!$saveDir) {
                    Write-Err "Save folder not found."
                    Start-Sleep -Seconds 2
                    continue
                }
                New-Item -ItemType Directory -Force -Path $Config.BackupRoot | Out-Null
                $result = Invoke-Backup -SaveDir $saveDir -Files (Get-TargetFiles) -Reason "manual"
                if ($result.Success) {
                    Write-Ok "Manual backup created!"
                    foreach ($r in $result.Results) {
                        Write-Host "  $r" -ForegroundColor Gray
                    }
                } else {
                    Write-Err "Backup failed - no files found or all copies failed."
                }
                Write-Host ""
                Read-Host "  Press Enter to continue"
            }
            "3" {
                if (!$saveDir) {
                    Write-Err "Save folder not found."
                    Start-Sleep -Seconds 2
                    continue
                }
                if (!(Test-Path $Config.BackupRoot)) {
                    Write-Warn "No backups exist yet."
                    Start-Sleep -Seconds 2
                    continue
                }
                Show-RestoreMenu -SaveDir $saveDir
            }
            "4" {
                Show-SettingsMenu
            }
            "5" {
                if (Test-Path $Config.BackupRoot) {
                    Start-Process explorer.exe $Config.BackupRoot
                } else {
                    Write-Warn "Backup folder doesn't exist yet. Run a backup first."
                    Start-Sleep -Seconds 2
                }
            }
            "6" {
                Write-Host ""
                $newPath = Read-Host "  Enter full path to SaveGames folder"
                if ($newPath -ne "" -and (Test-Path $newPath)) {
                    $saveDir = $newPath
                    Write-Ok "Save folder set to: $newPath"
                } elseif ($newPath -ne "") {
                    Write-Err "Path does not exist: $newPath"
                }
                Start-Sleep -Seconds 1
            }
            "0" {
                Write-Host ""
                Write-Host "  Stay safe out there, bounty hunter." -ForegroundColor Cyan
                Write-Host ""
                return
            }
            default { }
        }
    }
}

# ============================================================
#  ENTRY POINT
# ============================================================

# Set console title
$Host.UI.RawUI.WindowTitle = "HOL2 SaveGuard"

Show-MainMenu
