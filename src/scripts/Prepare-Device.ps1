[CmdletBinding()]
param (
    [string]$BackupRootPath = "C:\Users\beastmp\OneDrive\Backups",
    [string]$DateFormat = "yyyyMMdd_HHmmss",

    # Switch parameters for toggling steps in Run-WindowsUpdate
    [switch]$SkipBackup,
    [switch]$SkipCheckRequirements
)

function Set-ExecutionPolicy {[CmdletBinding()]param()
    try {Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Force;Write-Host "[INFO] Execution policy set to Unrestricted for the current session." -ForegroundColor Green}
    catch {Write-Host "[ERROR] Failed to set execution policy: $_" -ForegroundColor Red;exit}
}

function Check-SystemRequirements {[CmdletBinding()]param()
    Write-Host "[INFO] Checking system requirements for Windows 11..." -ForegroundColor Cyan

    # Check the partition style of the boot disk
    $bootDisk = Get-Disk | Where-Object { $_.IsBoot -eq $true }
    if ($bootDisk) {
        Write-Host "[INFO] Boot Disk: $($bootDisk.Number)" -ForegroundColor Green
        Write-Host "[INFO] Partition Style: $($bootDisk.PartitionStyle)" -ForegroundColor Green
    } else {Write-Host "[ERROR] No boot disk found." -ForegroundColor Red;return}
    Check-TPM
    Check-SecureBoot
    Check-CPU
    Check-RAM
    Check-Storage
    Check-BIOS
}

function Check-TPM {[CmdletBinding()]param()
    $tpm = Get-CimInstance -Namespace "Root\CIMv2\Security\MicrosoftTpm" -ClassName Win32_Tpm
    if ($tpm) {if ($tpm.SpecVersion -ge "2.0") {Write-Host "[INFO] TPM 2.0 is present." -ForegroundColor Green}
    else{Write-Host "[ERROR] TPM version is less than 2.0." -ForegroundColor Red}}
    else{
        Write-Host "[ERROR] TPM is not present." -ForegroundColor Red
        Write-Host "[INFO] To enable TPM, please follow these steps:" -ForegroundColor Cyan
        Write-Host "1. Restart your computer and enter the BIOS/UEFI settings (usually by pressing F2, DEL, or ESC during boot)." -ForegroundColor Yellow
        Write-Host "2. Look for a setting related to 'TPM', 'Security', or 'Trusted Computing'." -ForegroundColor Yellow
        Write-Host "3. Enable TPM and save your changes." -ForegroundColor Yellow
        Write-Host "4. Restart your computer." -ForegroundColor Yellow
    }
}

function Check-SecureBoot {[CmdletBinding()]param()
    $secureBoot = Confirm-SecureBootUEFI
    if ($secureBoot) {Write-Host "[INFO] Secure Boot is enabled." -ForegroundColor Green}
    else{
        Write-Host "[ERROR] Secure Boot is not enabled." -ForegroundColor Red
        Write-Host "[INFO] To enable Secure Boot, please follow these steps:" -ForegroundColor Cyan
        Write-Host "1. Restart your computer and enter the BIOS/UEFI settings (usually by pressing F2, DEL, or ESC during boot)." -ForegroundColor Yellow
        Write-Host "2. Look for a setting related to 'Secure Boot' under the 'Boot' or 'Security' tab." -ForegroundColor Yellow
        Write-Host "3. Enable Secure Boot and save your changes." -ForegroundColor Yellow
        Write-Host "4. Restart your computer." -ForegroundColor Yellow
    }
}

function Check-CPU {[CmdletBinding()]param()
    $cpu = Get-CimInstance Win32_Processor
    if ($cpu) {Write-Host "[INFO] CPU: $($cpu.Name)" -ForegroundColor Green}
    else {Write-Host "[ERROR] No compatible CPU found." -ForegroundColor Red}
}

function Check-RAM {[CmdletBinding()]param()
    $ram = (Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB
    if ($ram -ge 4) {Write-Host "[INFO] RAM: $([math]::round($ram, 2)) GB" -ForegroundColor Green}
    else {Write-Host "[ERROR] Insufficient RAM. Minimum 4 GB required." -ForegroundColor Red}
}

function Check-Storage {[CmdletBinding()]param()
    $storage = Get-PSDrive -PSProvider FileSystem | Where-Object {$_.Used -lt 64GB}
    if ($storage) {Write-Host "[INFO] Sufficient storage available." -ForegroundColor Green}
    else {Write-Host "[ERROR] Insufficient storage. Minimum 64 GB required." -ForegroundColor Red}
}

function Check-BIOS {[CmdletBinding()]param()
    $bios = Get-CimInstance Win32_BIOS
    Write-Host "[INFO] Current BIOS Version: $($bios.SMBIOSBIOSVersion)" -ForegroundColor Green
    Write-Host "[INFO] Manufacturer: $($bios.Manufacturer)" -ForegroundColor Green
    Write-Host "[WARNING] Please visit the manufacturer's website to check for BIOS updates." -ForegroundColor Yellow
    Write-Host "[INFO] Search for your motherboard model and look for the latest BIOS version." -ForegroundColor Yellow
}

function Backup-ApplicationData {[CmdletBinding()]param([Parameter()][string]$BackupRootPath = "C:\Users\beastmp\OneDrive\Backups",[Parameter()][string]$DateFormat = "yyyyMMdd_HHmmss")
    Write-Host "[INFO] Starting application data backup..." -ForegroundColor Cyan
    $timestamp = Get-Date -Format $DateFormat
    $DataBackupPath = Join-Path -Path $BackupRootPath -ChildPath $timestamp
    New-BackupDirectory -Path $DataBackupPath
    $locations = @{
        "CapCut" = @{
            SourcePath = "C:\Users\beastmp\AppData\Local\CapCut"
            IncludeDirectories = @("User Data\Projects", "Videos")  # Specify subdirectories to include
            IncludeFiles = @()            # Specify file patterns to include
            ExcludeDirectories = @()  # Specify subdirectories to include
            ExcludeFiles = @()            # Specify file patterns to include
        }
        "Cookn" = @{
            SourcePath = "C:\Users\beastmp\AppData\Local\DVO\Cook'n12App"
            IncludeDirectories = @("configuration")              # Specify subdirectories to include
            IncludeFiles = @("*.txt","*.ini","*.log","*.properties","*.dat","drive")                      # Specify file patterns to include
            ExcludeDirectories = @()  # Specify subdirectories to include
            ExcludeFiles = @("*BounceHouse*")            # Specify file patterns to include
        }
        "PowerAutomate" = @{
            SourcePath = "C:\Users\beastmp\AppData\Local\Microsoft\Power Automate Desktop"
            IncludeDirectories = @()                         # No specific directories to include
            IncludeFiles = @()                       # Specify file patterns to include
            ExcludeDirectories = @()  # Specify subdirectories to include
            ExcludeFiles = @()            # Specify file patterns to include
        }
    }
    foreach ($location in $locations.GetEnumerator()) {
        $locationName = $location.Key
        $locationDetails = $location.Value
        Backup-Location -SourcePath $locationDetails.SourcePath -DestinationPath (Join-Path -Path $DataBackupPath -ChildPath $locationName) -IncludeDirectories $locationDetails.IncludeDirectories -IncludeFiles $locationDetails.IncludeFiles -ExcludeDirectories $locationDetails.ExcludeDirectories -ExcludeFiles $locationDetails.ExcludeFiles
    }
    Create-ZipArchive -BackupPath $DataBackupPath
}

function New-BackupDirectory {[CmdletBinding()]param([Parameter()][string]$Path)
    if (-not (Test-Path -Path $Path)) {New-Item -ItemType Directory -Path $Path -Force | Out-Null}
}

function Set-FullPermissions {
    param (
        [string]$Path
    )

    Write-Host "[INFO] Granting full permissions to the current user on $Path..." -ForegroundColor Cyan

    try {
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        icacls $Path /grant "${currentUser}:(OI)(CI)F" /T
        Write-Host "[INFO] Full permissions granted to $currentUser on $Path." -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Failed to set permissions: $_" -ForegroundColor Red
    }
}

function Backup-Location {[CmdletBinding()]param(
    [Parameter()][string]$SourcePath,
    [Parameter()][string]$DestinationPath,
    [Parameter()][string[]]$IncludeDirectories,  # Directories to include
    [Parameter()][string[]]$IncludeFiles,          # Files or patterns to include
    [Parameter()][string[]]$ExcludeDirectories,    # Directories to exclude
    [Parameter()][string[]]$ExcludeFiles           # Files or patterns to exclude
)
    if (Test-Path -Path $SourcePath) {
        Write-Host "[INFO] Backing up from $SourcePath..." -ForegroundColor Cyan
        New-BackupDirectory -Path $DestinationPath
        $SourcePath
                
        # Filter and backup only specified directories
        foreach ($dir in $IncludeDirectories) {
            $fullPath = Join-Path -Path $SourcePath -ChildPath $dir
            if (Test-Path -Path $fullPath) {
                Write-Host "[INFO] Backing up directory: $fullPath" -ForegroundColor Cyan
                robocopy $fullPath $DestinationPath\$dir /E /ZB /R:3 /W:5 /LOG+:$DestinationPath\backup_log.txt
            } else {
                Write-Host "[WARNING] Directory $fullPath does not exist. Skipping." -ForegroundColor Yellow
            }
        }

        if (-not $IncludeDirectories) {
            $IncludeDirectories = Get-ChildItem -Path $SourcePath -Directory | Select-Object -ExpandProperty Name
        }

        # Filter and backup only specified directories
        foreach ($dir in $IncludeDirectories) {
            if ($ExcludeDirectories -notcontains $dir) {
                $fullPath = Join-Path -Path $SourcePath -ChildPath $dir
                if (Test-Path -Path $fullPath) {
                    Write-Host "[INFO] Backing up directory: $fullPath" -ForegroundColor Cyan
                    robocopy $fullPath $DestinationPath\$dir /E /ZB /R:3 /W:5 /LOG+:$DestinationPath\backup_log.txt
                } else {
                    Write-Host "[WARNING] Directory $fullPath does not exist. Skipping." -ForegroundColor Yellow
                }
            } else {
                Write-Host "[WARNING] Excluding directory: $dir" -ForegroundColor Yellow
            }
        }

        if (-not $IncludeFiles) {
            $IncludeFiles = @("*")  # Use wildcard to include all files
        }

        # Filter and backup specified files or files matching patterns
        foreach ($pattern in $IncludeFiles) {
            if ($ExcludeFiles -notcontains $pattern) {
                Get-ChildItem -Path $SourcePath -Filter $pattern | ForEach-Object {
                    $fileDestination = Join-Path -Path $DestinationPath -ChildPath $_.Name
                    Write-Host "[INFO] Backing up file: $($_.FullName) to $fileDestination" -ForegroundColor Cyan
                    Copy-Item -Path $_.FullName -Destination $fileDestination -Force
                }
            } else {
                Write-Host "[WARNING] Excluding file pattern: $pattern" -ForegroundColor Yellow
            }
        }

        Get-ChildItem -Path $DestinationPath -Recurse | ForEach-Object {
            $newName = $_.Name -replace '[<>:"/\\|?*]|[^\x00-\x7F]', '_'  # Replace invalid and non-English characters with underscore
            if ($newName -ne $_.Name) {
                Rename-Item -Path $_.FullName -NewName $newName -Force
                Write-Host "[INFO] Renamed '$_' to '$newName'" -ForegroundColor Yellow
            }
        }

        # Set full permissions on the backup location
        Set-FullPermissions -Path $DestinationPath
    } else {Write-Host "[WARNING] Source path $SourcePath does not exist. Skipping." -ForegroundColor Yellow}
}

function Create-ZipArchive {[CmdletBinding()]param([Parameter()][string]$BackupPath)

    Write-Host "[INFO] Creating zip archive of backup..." -ForegroundColor Cyan
    $zipPath = "$BackupPath.zip"
    try {
        Compress-Archive -Path $BackupPath -DestinationPath $zipPath -Force
        Write-Host "[INFO] Successfully created zip archive at: $zipPath" -ForegroundColor Green
        #Remove-Item -Path $BackupPath -Recurse -Force
        Write-Host "[INFO] Removed original backup folder after successful compression" -ForegroundColor Green
    } catch {Write-Host "[ERROR] Failed to create zip archive: $_" -ForegroundColor Red}

    Write-Host "[INFO] Application data backup completed. Backup location: $zipPath" -ForegroundColor Green
}

function Test-IsAdmin {[CmdletBinding()]param()
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Start-ElevatePrivileges {[CmdletBinding()]param()
    Write-Host "[INFO] Elevating to admin privileges..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
}

if (-not $SkipBackup) {Write-Host "[INFO] Backing up application data..." -ForegroundColor Cyan;Backup-ApplicationData -BackupRoot $BackupRootPath -DateFormat $DateFormat}
else {Write-Host "[INFO] Skipping application data backup." -ForegroundColor Yellow}
if (-not $SkipCheckRequirements) {Check-SystemRequirements}
else {Write-Host "[INFO] Skipping system requirements check." -ForegroundColor Yellow}
