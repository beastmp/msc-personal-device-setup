[CmdletBinding()]
param()

function Log-Message {[CmdletBinding()]param([Parameter()][ValidateSet("INFO","SCSS","ERRR","WARN","DBUG","VRBS","PROG")][string]$LogLevel="INFO",[Parameter()][string]$Message)
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $color = switch ($LogLevel) {"SCSS"{"Green"}"ERRR"{"Red"}"WARN"{"Yellow"}"DBUG"{"Cyan"}"VRBS"{"DarkYellow"}"PROG"{"Magenta"}default{"White"}}
    if ($LogLevel -eq "DBUG" -and -not ($PSBoundParameters.Debug -eq $true)) {return}
    if ($LogLevel -eq "VRBS" -and -not ($PSBoundParameters.Verbose -eq $true)) {return}
    Write-Host "[$timestamp] [$LogLevel] $Message" -ForegroundColor $color
}

#Done during Windows Setup
function Set-DeviceName {
    param (
        [string]$NewDeviceName
    )

    Write-Host "[INFO] Changing device name to $NewDeviceName..." -ForegroundColor Cyan

    try {
        $currentComputerName = $env:COMPUTERNAME
        Rename-Computer -NewName $NewDeviceName -Force
        Write-Host "[INFO] Device name changed from $currentComputerName to $NewDeviceName. The system will restart." -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Failed to change device name: $_" -ForegroundColor Red
    }
}

#Done during windows install
function Initialize-SystemDrives {
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$CPartitionSizeGB = 250, # Default C: drive size in GB
        [Parameter()]
        [string]$DPartitionLabel = "Data"
    )

    Write-Host "[INFO] Starting system drive initialization..." -ForegroundColor Cyan

    # Get the system disk
    $systemDisk = Get-Disk | Where-Object { $_.IsBoot -eq $true }
    
    if (-not $systemDisk) {
        Write-Host "[ERROR] Could not find system disk" -ForegroundColor Red
        return
    }

    try {
        # Convert desired C: partition size to bytes
        $cPartitionSize = $CPartitionSizeGB * 1GB

        # Get current partition layout
        $existingPartitions = Get-Partition -DiskNumber $systemDisk.Number

        # Check if disk is already partitioned
        if ($existingPartitions.Count -gt 2) { # More than 2 because of System Reserved partition
            Write-Host "[WARNING] Disk is already partitioned. Skipping partitioning to prevent data loss." -ForegroundColor Yellow
            return
        }

        Write-Host "[INFO] Resizing system partition..." -ForegroundColor Cyan
        
        # Resize the Windows partition (C:)
        $systemPartition = Get-Partition -DiskNumber $systemDisk.Number | Where-Object { $_.DriveLetter -eq 'C' }
        Resize-Partition -InputObject $systemPartition -Size $cPartitionSize

        # Calculate remaining space for D: drive
        $remainingSpace = $systemDisk.Size - $cPartitionSize

        # Create D: partition with remaining space
        Write-Host "[INFO] Creating Data partition (D:)..." -ForegroundColor Cyan
        $newPartition = New-Partition -DiskNumber $systemDisk.Number -UseMaximumSize -DriveLetter 'D'
        
        # Format the new partition
        Format-Volume -DriveLetter 'D' -FileSystem NTFS -NewFileSystemLabel $DPartitionLabel -Confirm:$false

        Write-Host "[INFO] Drive initialization completed successfully!" -ForegroundColor Green
        Write-Host "C: Drive Size: $CPartitionSizeGB GB" -ForegroundColor Green
        Write-Host "D: Drive Size: $([math]::Round($remainingSpace/1GB, 2)) GB" -ForegroundColor Green

    }
    catch {
        Write-Host "[ERROR] Failed to initialize drives: $_" -ForegroundColor Red
    }
}

function Set-DisplayLocation {
    Add-Type -AssemblyName System.Windows.Forms

    # Get display settings
    [System.Windows.Forms.Screen]::AllScreens
    $displays = [System.Windows.Forms.Screen]::AllScreens

    if ($displays.Length -lt 2) {
        Write-Host "At least two monitors are required."
        return
    }

    $primaryMonitor = $displays[0]
    $secondaryMonitor = $displays[1]
    $tertiaryMonitor = $displays[2]

    $primaryMonitor.DeviceName
    #$primaryMonitor.Bounds = New-Object System.Drawing.Rectangle(0, 0, 1920, 1080)

    $secondaryMonitor.DeviceName
    #$secondaryMonitor.Bounds = New-Object System.Drawing.Rectangle(-1920, -43, 1920, 1080)

    $tertiaryMonitor.DeviceName
    #$secondaryMonitor.Bounds = New-Object System.Drawing.Rectangle(1920, -43, 1920, 1080)

    #[System.Windows.Forms.Screen]::PrimaryScreen = $primaryMonitor
    #[System.Windows.Forms.Screen]::AllScreens = $displays
}

function Set-PowerConfig {
    $CustomConfig = powercfg /duplicatescheme 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c
    $CustomConfig
    $regEx = '(\{){0,1}[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}(\}){0,1}'
    $CustomConfigGUID = [regex]::Match($CustomConfig,$regEx).Value
    powercfg /changename $CustomConfigGUID Custom
    powercfg /setactive $CustomConfigGUID
    powercfg /change monitor-timeout-ac 0
    powercfg /change monitor-timeout-dc 0
    powercfg /change disk-timeout-ac 0
    powercfg /change disk-timeout-dc 0
    powercfg /change standby-timeout-ac 0
    powercfg /change standby-timeout-dc 0
    powercfg /change hibernate-timeout-ac 0
    powercfg /change hibernate-timeout-dc 0
}

function Get-DriveList {
    [CmdletBinding()]
    param()

    Write-Host "[INFO] Retrieving list of mounted drives..." -ForegroundColor Cyan

    try {
        # Get physical drives
        Write-Host "`nPhysical Drives:" -ForegroundColor Green
        Write-Host "----------------"
        Get-Volume | Where-Object {$_.DriveType -eq 'Fixed'} | Format-Table -AutoSize @(
            @{Label="Drive Letter"; Expression={$_.DriveLetter}},
            @{Label="Label"; Expression={$_.FileSystemLabel}},
            @{Label="Size (GB)"; Expression={[math]::Round($_.Size/1GB, 2)}},
            @{Label="Free Space (GB)"; Expression={[math]::Round($_.SizeRemaining/1GB, 2)}},
            @{Label="File System"; Expression={$_.FileSystem}}
        )

        # Get virtual drives
        Write-Host "`nVirtual Drives:" -ForegroundColor Green 
        Write-Host "---------------"
        Get-Disk | Where-Object {$_.Location -like "*.vhd*"} | ForEach-Object {
            $disk = $_
            Get-Partition -DiskNumber $disk.Number | Where-Object {$_.Type -eq "Basic"} | Format-Table -AutoSize @(
                @{Label="Drive Letter"; Expression={$_.DriveLetter}},
                @{Label="VHD Path"; Expression={$disk.Location}},
                @{Label="Size (GB)"; Expression={[math]::Round($_.Size/1GB, 2)}}
            )
        }

        # Get network shares
        Write-Host "`nNetwork Shares:" -ForegroundColor Green
        Write-Host "---------------"
        Get-PSDrive -PSProvider FileSystem | Where-Object {$_.DisplayRoot -like "\\*"} | Format-Table -AutoSize @(
            @{Label="Drive Letter"; Expression={$_.Name + ":"}},
            @{Label="Network Path"; Expression={$_.DisplayRoot}},
            @{Label="Used (GB)"; Expression={[math]::Round(($_.Used/1GB), 2)}},
            @{Label="Free (GB)"; Expression={[math]::Round(($_.Free/1GB), 2)}}
        )

        # Get all drives using System.IO.DriveInfo
        Write-Host "`nAll Drives (System.IO.DriveInfo):" -ForegroundColor Green
        Write-Host "--------------------------------"
        [System.IO.DriveInfo]::GetDrives() | Format-Table -AutoSize @(
            @{Label="Drive"; Expression={$_.Name}},
            @{Label="Type"; Expression={$_.DriveType}},
            @{Label="Label"; Expression={$_.VolumeLabel}},
            @{Label="Format"; Expression={$_.DriveFormat}},
            @{Label="Size (GB)"; Expression={if($_.IsReady){[math]::Round($_.TotalSize/1GB, 2)}else{"N/A"}}},
            @{Label="Free (GB)"; Expression={if($_.IsReady){[math]::Round($_.AvailableFreeSpace/1GB, 2)}else{"N/A"}}}
        )
    }
    catch {
        Write-Host "[ERROR] Failed to retrieve drive information: $_" -ForegroundColor Red
    }
}

function Set-GoogleDriveMapping {
    param (
        [string]$GoogleDriveEmail,
        [string]$DesiredLetter
    )

    Write-Host "[INFO] Changing Google Drive letter for $GoogleDriveEmail..." -ForegroundColor Cyan

    $emailKeyMap = @{
        'blackwidowmilf143@gmail.com' = '108397542208085523603'
        'jennaloiacano@gmail.com' = '114732391918949850463'
        'beastmp13@gmail.com' = '117071222561899795506'
    }

    $registryPath = "HKCU:\SOFTWARE\Google\DriveFS"
    $valueName = "PerAccountPreferences"

    try {
        if (-not (Test-Path $registryPath)) {
            New-Item -Path $registryPath -Force | Out-Null
            Write-Host "[INFO] Created registry path: $registryPath" -ForegroundColor Gray
        }

        $currentValue = Get-ItemProperty -Path $registryPath -Name $valueName -ErrorAction SilentlyContinue
        $preferences = if ($currentValue) { $currentValue.PerAccountPreferences | ConvertFrom-Json } else { Initialize-GoogleDrivePreferences }

        $key = $emailKeyMap[$GoogleDriveEmail]
        $accountPref = $preferences.per_account_preferences | Where-Object { $_.key -eq $key }
        if ($accountPref) {
            $accountPref.value.mount_point_path = $DesiredLetter
        }

        $newValueData = $preferences | ConvertTo-Json -Compress
        Set-ItemProperty -Path $registryPath -Name $valueName -Value $newValueData
        Write-Host "[INFO] Successfully changed Google Drive letter for $GoogleDriveEmail to drive $DesiredLetter" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Failed to change Google Drive letter: $_" -ForegroundColor Red
    }
}

function Initialize-GoogleDrivePreferences {
    return @{
        per_account_preferences = @(
            @{key = '108397542208085523603'; value = @{ mount_point_path = 'W' }},
            @{key = '114732391918949850463'; value = @{ mount_point_path = 'X' }},
            @{key = '117071222561899795506'; value = @{ mount_point_path = 'Y' }}
        )
    }
}

function Set-DriveLettersAndLabels {
    $ExternalDisk = Get-Disk | Where-Object { $_.Number -eq 1 }  # Replace 0 with your disk number
    $ExternalPartition = Get-Partition -DiskNumber $ExternalDisk.Number | Where-Object {$_.PartitionNumber -eq 1}
    $ExternalPartition | Set-Partition -NewDriveLetter "Z"
    $ExternalVolume = Get-Volume -Partition $ExternalPartition
    $ExternalVolume | Set-Volume -NewFileSystemLabel "External"
    $InternalDisk = Get-Disk | Where-Object { $_.Number -eq 0 }  # Replace 0 with your disk number
    $PrimaryPartition = Get-Partition -DiskNumber $InternalDisk.Number | Where-Object {$_.PartitionNumber -eq 3}
    $PrimaryPartition | Set-Partition -NewDriveLetter "C"
    $RecoveryPartition = Get-Partition -DiskNumber $InternalDisk.Number | Where-Object {$_.PartitionNumber -eq 4}
    $RecoveryPartition | Set-Partition -NewDriveLetter "R"
    $DataPartition = Get-Partition -DiskNumber $InternalDisk.Number | Where-Object {$_.PartitionNumber -eq 5}
    $DataPartition | Set-Partition -NewDriveLetter "D"
    $PrimaryVolume = Get-Volume -Partition $PrimaryPartition
    $PrimaryVolume | Set-Volume -NewFileSystemLabel "Primary"
    $RecoveryVolume = Get-Volume -Partition $RecoveryPartition
    $RecoveryVolume | Set-Volume -NewFileSystemLabel "Recovery"
    $DataVolume = Get-Volume -Partition $DataPartition
    $DataVolume | Set-Volume -NewFileSystemLabel "Data"
}

function Test-WindowsSandbox {
    [CmdletBinding()]
    param()

    try {
        # Check multiple indicators for Windows Sandbox environment
        $computerInfo = Get-ComputerInfo
        $sandboxProcess = Get-Process -Name "WindowsSandboxClient" -ErrorAction SilentlyContinue
        $envPath = $env:LOCALAPPDATA
        
        # Windows Sandbox has specific characteristics:
        # - Model name contains "Windows Sandbox" or is "Virtual Machine"
        # - Manufacturer is "Microsoft Corporation" 
        # - WindowsSandboxClient process may be running
        # - Environment paths contain specific sandbox indicators
        $isSandbox = ($computerInfo.CsModel -like "*Windows Sandbox*" -or
                     $computerInfo.CsModel -eq "Virtual Machine" -or 
                     $computerInfo.CsManufacturer -eq "Microsoft Corporation" -or
                     $null -ne $sandboxProcess -or
                     $envPath -like "*Windows\Containers\WindowsSandbox*")
        
        if ($isSandbox) {
            Write-Host "[INFO] Detected Windows Sandbox environment" -ForegroundColor Green
        }
        
        return $isSandbox
    }
    catch {
        Write-Host "[ERROR] Failed to determine if running in Windows Sandbox: $_" -ForegroundColor Red
        return $false
    }
}

function Restore-FromBackup {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$BackupPath = "C:\Users\beastmp\OneDrive\Backups",
        [Parameter()]
        [string]$DateFormat = "yyyyMMdd_HHmmss"
    )

    Write-Host "[INFO] Starting restoration process..." -ForegroundColor Cyan

    # Get the latest backup folder
    $latestBackup = Get-ChildItem -Path $BackupPath -Directory | 
                    Sort-Object LastWriteTime -Descending | 
                    Select-Object -First 1

    if (-not $latestBackup) {
        Write-Host "[ERROR] No backup found in $BackupPath" -ForegroundColor Red
        return
    }

    Write-Host "[INFO] Restoring from backup: $($latestBackup.FullName)" -ForegroundColor Green

    # Restore Installed Software
    $softwarePath = Join-Path -Path $latestBackup.FullName -ChildPath "InstalledSoftware"
    if (Test-Path "$softwarePath\InstalledSoftware.json") {
        Write-Host "[INFO] Restoring installed software..." -ForegroundColor Cyan
        
        # Call Personal_ToolSetup.ps1 with the InstalledSoftware.json file
        $toolSetupScript = "C:\Path\To\Your\Personal_ToolSetup.ps1"  # Update this path as necessary
        $installedSoftwareJson = "$softwarePath\InstalledSoftware.json"

        if (Test-Path $toolSetupScript) {
            Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$toolSetupScript`" `"$installedSoftwareJson`"" -NoNewWindow -Wait
            Write-Host "[INFO] Installed software restoration initiated." -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Personal_ToolSetup.ps1 not found at $toolSetupScript" -ForegroundColor Red
        }
    }

    # Restore User Data
    $userDataPath = Join-Path -Path $latestBackup.FullName -ChildPath "UserData"
    if (Test-Path $userDataPath) {
        Write-Host "[INFO] Restoring user data..." -ForegroundColor Cyan
        Copy-Item -Path $userDataPath\* -Destination "$env:USERPROFILE" -Recurse -Force
        Write-Host "[INFO] User data restored." -ForegroundColor Green
    }

    Write-Host "[SUCCESS] Restoration process completed successfully!" -ForegroundColor Green
}

function Install-PSModule {[CmdletBinding()]param([Parameter()][string]$ModuleName,[Parameter()][string]$RepositoryName,[Parameter()][string]$Version,[Parameter()][bool]$WhatIfFlag=$false)
    #Remove-PSModule -ModuleName $ModuleName -WhatIfFlag:$WhatIfFlag
    $installParams = @{Name=$ModuleName;Force=$true;Confirm=$false}
    if ($RepositoryName) {$installParams.Repository = $RepositoryName}
    if ($Version) {$installParams.RequiredVersion = $Version}
    #Log-Message "INFO" "Installing $ModuleName"+(if($Version){" v$Version"}else{""})+(if($RepositoryName){" from $RepositoryName..."}else{"..."}) -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    try {Install-Module @installParams; Log-Message "INFO" "$ModuleName installed successfully" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
    catch {Log-Message "ERRR" "Unable to install $ModuleName" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
    return $true
}

function Validate-SandboxFeature {
    $sandboxFeature = Get-WindowsOptionalFeature -Online -FeatureName "Containers-DisposableClientVM"
    if ($sandboxFeature.State -ne "Enabled") {
        Write-Host "[ERROR] Windows Sandbox feature is not enabled. Enabling it now..." -ForegroundColor Yellow
        Enable-WindowsOptionalFeature -Online -FeatureName "Containers-DisposableClientVM" -All -NoRestart
        Write-Host "[WARNING] Please restart your computer to complete Windows Sandbox installation" -ForegroundColor Yellow
        throw "Sandbox feature not enabled"
    }
}

function Set-ExplorerOptions {
    $Path = "Registry::HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-ItemProperty -Path $Path -Name 'Hidden' -Value 00000001
    Set-ItemProperty -Path $Path -Name 'HideFileExt' -Value 00000000
    New-ItemProperty -Path $Path -Name "TaskbarAl" -Value "0" -PropertyType Dword -Force
    $TargetProcess = Get-Process "explorer" -ErrorAction SilentlyContinue
    $TargetProcess | Stop-Process -Force
}

function Add-ToContextMenus {
    #Not working in Windows 11
    $Path = "Registry::HKEY_CLASSES_ROOT\AllFilesystemObjects\shellex\ContextMenuHandlers"
    $MoveToKey = New-Item -Path $Path -Name 'Move To' -Value "{C2FBB631-2971-11D1-A18C-00C04FD75D13}"
    $CopyToKey = New-Item -Path $Path -Name 'Copy To' -Value "{C2FBB630-2971-11D1-A18C-00C04FD75D13}"
    
#    $Path = "Registry::HKEY_CLASSES_ROOT\AllFilesystemObjects\shell"
#    $CopyAsKey = New-Item -Path $Path -Name 'windows.copyaspath'
#    New-ItemProperty -Path $CopyAsKey.PSPath -Name "CanonicalName" -PropertyType String -Value "{707C7BC6-685A-4A4D-A275-3966A5A3EFAA}"
#    New-ItemProperty -Path $CopyAsKey.PSPath -Name "CommandStateHandler" -PropertyType String -Value "{3B1599F9-E00A-4BBF-AD3E-B3F99FA87779}"
#    New-ItemProperty -Path $CopyAsKey.PSPath -Name "CommandStateSync" -PropertyType String -Value ""
#    New-ItemProperty -Path $CopyAsKey.PSPath -Name "Description" -PropertyType String -Value "@shell32.dll,-30336"
#    New-ItemProperty -Path $CopyAsKey.PSPath -Name "Icon" -PropertyType String -Value "imageres.dll,-5302"
#    New-ItemProperty -Path $CopyAsKey.PSPath -Name "InvokeCommandOnSelection" -PropertyType DWord -Value 00000001
#    New-ItemProperty -Path $CopyAsKey.PSPath -Name "MUIVerb" -PropertyType String -Value "@shell32.dll,-30329"
#    New-ItemProperty -Path $CopyAsKey.PSPath -Name "VerbHandler" -PropertyType String -Value "{f3d06e7c-1e45-4a26-847e-f9fcdee59be0}"
#    New-ItemProperty -Path $CopyAsKey.PSPath -Name "VerbName" -PropertyType String -Value "copyaspath"
}

function Set-MiscRegistry {
    #Set NumLock always on
    $Path = "Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard"
    Set-ItemProperty -Path $Path -Name 'InitialKeyboardIndicators' -Value "2"
}

function Initialize-System {
    Rename-LocalUser -Name "beast" -NewName "beastmp"
	#-After renaming local user the user profile folder will need to be renamed as well
	#--https://learn.microsoft.com/en-us/answers/questions/2126959/how-to-change-user-folder-name-in-windows-11
	#--https://answers.microsoft.com/en-us/windows/forum/all/how-do-i-change-my-username-including-my-user/85ac651c-d736-45f8-b2ff-81101e703ed5
    Start-Process -FilePath "C:\Windows\Resources\Themes\dark.theme"
    Set-DriveLettersAndLabels
    Start-Process "DisplaySwitch.exe" -ArgumentList "/extend"
    Set-DisplayLocation
    Set-PowerConfig
    Set-ExplorerOptions
    Add-ToContextMenus
    Set-MiscRegistry
    Set-NetFirewallProfile -Profile Domain, Public, Private -Enabled False

    Set-ExecutionPolicy Unrestricted -Force -Scope LocalMachine
    Set-ExecutionPolicy Unrestricted -Force -Scope CurrentUser
    Set-ExecutionPolicy Unrestricted -Force -Scope Process
    Install-PackageProvider -Name NuGet -Force
    Install-PSModule -ModuleName Microsoft.WinGet.Client -RepositoryName PSGallery
    Repair-WinGetPackageManager
    winget settings --enable LocalManifestFiles
    winget settings --enable InstallerHashOverride
    winget source update
	
	
	#OTHER ITEMS THAT NEED RESEARCH
	#-ProgramFiles/WindowsApp folder is inacessible even by admin user
	#--https://www.supportyourtech.com/tech/how-to-access-windowsapps-folder-in-windows-11-step-by-step-guide/
	#--https://learn-powershell.net/2014/06/24/changing-ownership-of-file-or-folder-using-powershell/
	#--Takeown /F "C:\Example\Folder" /R /D Y
	#--icacls "C:\Example\Folder" /grant YourUsername:F /T
	#-Device Modules are blocked from running on windows 11. Need to diable Local Security Authority protection and Microsoft Vulnerable Driver Blocklist
	#--https://answers.microsoft.com/en-us/windows/forum/all/i-keep-getting-this-module-is-blocked-from-loading/df1c2f9e-cfd4-4a28-9071-3946de3e1497
	#--https://mywindowshub.com/enable-or-disable-local-security-authority-lsa-protection-in-windows-11/
}

function Create-TaskbarLayout {
    $TaskbarLayout =
@"
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate
    xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification"
    xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout"
    xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout"
    xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout"
    Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Replace">
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
        <taskbar:UWA AppUserModelID="windows.immersivecontrolpanel_cw5n1h2txyewy!microsoft.windows.immersivecontrolpanel" />
        <taskbar:UWA AppUserModelID="Microsoft.Copilot_8wekyb3d8bbwe!App" />
        <taskbar:UWA AppUserModelID="Microsoft.WindowsCalculator_8wekyb3d8bbwe!App" />
        <taskbar:UWA AppUserModelID="NotepadPlusPlus_7njy0v32s6xk6!NotepadPlusPlus" />
        <taskbar:UWA AppUserModelID="Microsoft.MicrosoftEdge.Stable_8wekyb3d8bbwe!App" />
        <taskbar:DesktopApp DesktopApplicationID="Microsoft.Windows.Explorer" />
        <taskbar:UWA AppUserModelID="Microsoft.OutlookForWindows_8wekyb3d8bbwe!Microsoft.OutlookforWindows" />
        <taskbar:UWA AppUserModelID="57540AMZNMobileLLC.AmazonAlexa_22t9g3sebte08!App" />
        <taskbar:UWA AppUserModelID="tv.plex.plexamp" />
        <taskbar:UWA AppUserModelID="com.reolink.app" />
        <taskbar:DesktopApp DesktopApplicationLinkPath="D:\Apps\Minecraft\Minecraft Launcher\MinecraftLauncher.exe" />
        <taskbar:DesktopApp DesktopApplicationLinkPath="D:\Apps\GIMP\GIMP\bin\gimp-2.10.exe" />
        <taskbar:DesktopApp DesktopApplicationLinkPath="D:\Apps\Audacity\Audacity.exe" />
        <taskbar:DesktopApp DesktopApplicationLinkPath="D:\Apps\Wondershare\Filmora\Wondershare Filmora Launcher.exe" />
        <taskbar:UWA AppUserModelID="Microsoft.WindowsTerminal_8wekyb3d8bbwe!App" />
        <taskbar:UWA AppUserModelID="Microsoft.VisualStudioCode" />
        <taskbar:UWA AppUserModelID="VisualStudio.72b87c39" />
        <taskbar:UWA AppUserModelID="Microsoft.PowerAutomateDesktop_8wekyb3d8bbwe!PAD.Console" />
        <taskbar:DesktopApp DesktopApplicationLinkPath="D:\Apps\Docker\Desktop\Docker Desktop.exe" />
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
 </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@
    
    $TaskbarLayout | Out-File "D:\Scripts\TaskbarLayout.xml" -Encoding utf8
    return "D:\Scripts\TaskbarLayout.xml"
}

function Get-InstalledAppsAndIDs {
    $StartApps = Get-StartApps
    $AppList = @()
    foreach ($App in $StartApps) {
        $AppID = $App.AppID
        $IDType = "Other"
        if ($App.Name -notlike "*install*") {
            if ($AppID -like "*!*") {$IDType = "AppUserModelID"}
            elseif ($AppID -match "^[A-Z]:\\" -and $AppID -like "*.exe") {$IDType = "DesktopApplicationLinkPath"}
            elseif ($AppID -like "*.*.*" -and $AppID -notlike "*/*" -and $AppID -notlike "*\*") {$IDType = "DesktopApplicationID"}
            $appObject = [PSCustomObject]@{Name = $App.Name;AppID = $AppID;IDType = $IDType}
        }
        $AppList += $appObject
    }
    $AppList = $AppList | Where-Object {$_.IDType -ne "Other"} | Sort-Object Name
    return $AppList
}

function Invoke-TaskbarLayout {
    $TaskbarLayout = Create-TaskbarLayout  # Update this path as necessary
    if (Test-Path $TaskbarLayout) {
        Write-Host "[INFO] Applying taskbar layout from $TaskbarLayout..." -ForegroundColor Cyan
        Import-StartLayout -LayoutPath $TaskbarLayout -MountPath $env:SystemDrive
        Write-Host "[INFO] Taskbar layout applied successfully." -ForegroundColor Green
    } else {
        Write-Host "[ERROR] Taskbar layout file not found at $TaskbarLayout" -ForegroundColor Red
    }
}

function Import-StartLayout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$LayoutPath,
        [Parameter(Mandatory=$true)]
        [string]$MountPath
    )

    Write-Host "[INFO] Importing Start layout from $LayoutPath..." -ForegroundColor Cyan

    try {
        $layoutFile = Join-Path -Path $MountPath -ChildPath "Users\Default\AppData\Local\Microsoft\Windows\Shell\LayoutModification.xml"
        Copy-Item -Path $LayoutPath -Destination $layoutFile -Force
        $TargetProcess = Get-Process "explorer" -ErrorAction SilentlyContinue
        $TargetProcess | Stop-Process -Force
        Write-Host "[INFO] Start layout imported successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Failed to import Start layout: $_" -ForegroundColor Red
    }
}

#Initialize-System
