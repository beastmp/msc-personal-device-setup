#region PARAMS
[CmdletBinding()]
param (
    [string]$ConfigPath = "$PSScriptRoot/../config/script_config.json",
    [ValidateSet("Install","Uninstall","Test")]
    [string]$Action = "Install",
    [switch]$TestingMode,
    [string]$ApplicationName,  # Optional, for single application
    [string]$ApplicationVersion  # Optional, for single application
)

# Load configuration
$script:Config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
$script:BinariesDirectory = $Config.directories.binaries
$script:ScriptsDirectory = $Config.directories.scripts
$script:StagingDirectory = $Config.directories.staging
$script:InstallDirectory = $Config.directories.install
$script:PostInstallDirectory = $Config.directories.postInstall
$script:LogDirectory = $Config.directories.logs
$script:SoftwareListFileName = $Config.files.softwareList

#region HELPERS
#region     LOG HELPERS
function Get-LogFileName {param([Parameter()][ValidateSet("Log","Transcript")][string]$LogType,[Parameter()][string]$Action,[Parameter()][string]$TargetName,[Parameter()][string]$Version)
    $ScriptName = $(Split-Path $MyInvocation.PSCommandPath -Leaf).Replace(".ps1", "")
    $DateTime   = Get-Date -f 'yyyyMMddHHmmss'
    $FileName   = $Config.logging.fileNameFormat.Replace("{LogType}", $LogType).Replace("{ScriptName}", $ScriptName).Replace("{Action}", $Action).Replace("{TargetName}", $TargetName).Replace("{Version}", $Version).Replace("{DateTime}", $DateTime)
    return $FileName
}

function Log-Message {[CmdletBinding()]param([Parameter()][ValidateSet("INFO","SCSS","ERRR","WARN","DBUG","VRBS","PROG")][string]$LogLevel="INFO",[Parameter()][string]$Message)
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $color = switch ($LogLevel) {"SCSS"{"Green"}"ERRR"{"Red"}"WARN"{"Yellow"}"DBUG"{"Cyan"}"VRBS"{"DarkYellow"}"PROG"{"Magenta"}default{"White"}}
    if ($LogLevel -eq "DBUG" -and -not ($PSBoundParameters.Debug -eq $true)) {return}
    if ($LogLevel -eq "VRBS" -and -not ($PSBoundParameters.Verbose -eq $true)) {return}
    Write-Host "[$timestamp] [$LogLevel] $Message" -ForegroundColor $color
}
#endregion
#region     PROCESS HELPERS
function Invoke-StartProcess {[CmdletBinding()]param([Parameter()][string]$Command,[Parameter()][object]$Arguments)
    if($Arguments -is [array]) {
        $Arguments = $Arguments -join ' '
    }
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.FileName = $Command
    if($Arguments) { $process.StartInfo.Arguments = $Arguments }
    $out = $process.Start()
    $out | Out-String
    $StandardError = $process.StandardError.ReadToEnd()
    $StandardOutput = $process.StandardOutput.ReadToEnd()
    $StandardError | Out-String
    $StandardOutput | Out-String
    $output = New-Object PSObject
    $output | Add-Member -type NoteProperty -name StandardOutput -Value $StandardOutput
    $output | Add-Member -type NoteProperty -name StandardError -Value $StandardError
    $output | Add-Member -type NoteProperty -name ExitCode -Value $process.ExitCode
    return $output
}

function Invoke-Process {[CmdletBinding()]param([Parameter()][string]$Path,[Parameter()][string]$Action,[Parameter()][string[]]$Application,[Parameter()][string[]]$Arguments)
    $FullArguments = $(@($Action) + $Application + $Arguments) | Where-Object { $_ -ne "" -and $_ -ne " " -and $null -ne $_ }
    $Command = "$Path $($FullArguments -join ' ')"
    $PowershellCommand = "Start-Process -FilePath '$Path' -ArgumentList '$FullArguments' -NoNewWindow -Wait"
    Log-Message "DBUG" "Command: $Command" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    Log-Message "DBUG" "Powershell Command: $PowershellCommand" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    $Process = Start-Process -FilePath "$Path" -ArgumentList $FullArguments -NoNewWindow -PassThru | Wait-Process
    return $Process
}

function Invoke-KillProcess {[CmdletBinding()]param([Parameter()][string]$ProcessName)
    Start-Sleep -Seconds 15
    $TargetProcess = Get-Process $ProcessName -ErrorAction SilentlyContinue
    if ($TargetProcess) {
        Log-Message "VRBS" "Closing $ProcessName..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
        $TargetProcess | Stop-Process -Force
        Log-Message "VRBS" "$ProcessName closed successfully" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
    else {Log-Message "WARN" "$ProcessName process not found" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
}
#endregion
#region     ENVIRONMENT HELPERS
function Set-EnvironmentVariable {[CmdletBinding()]param([Parameter()][string]$Name,[Parameter()][string]$Value)
    try{
        [System.Environment]::SetEnvironmentVariable($Name, $Value, [System.EnvironmentVariableTarget]::Machine)
        Log-Message "VRBS" "Environment variable $Name set to $Value" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    }
    catch{Log-Message "ERRR" "Unable to set environment variable $Name to $Value" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
    return $true
}

function Add-ToPath {[CmdletBinding()]param([Parameter()][string]$Value)
    $envPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)
    if ($envPath -notlike "*$Value*") {
        try{[System.Environment]::SetEnvironmentVariable("Path", "$envPath;$Value", [System.EnvironmentVariableTarget]::Machine); Log-Message "VRBS" "Added $Value to PATH" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
        catch{Log-Message "ERRR" "Unable to add $Value to PATH" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
    }
    return $true
}
#endregion
#region     FILE SYSTEM HELPERS
function Add-Folders {[CmdletBinding()]param([Parameter()][string]$DirPath)
    if (-Not (Test-Path -Path $DirPath)) {
        try{New-Item -ItemType Directory -Path $DirPath -Force | Out-Null; Log-Message "VRBS" "$DirPath directory created successfully" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
        catch{Log-Message "ERRR" "Unable to create $DirPath directory" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
    }
    return $true
}

function Add-SymLink {[CmdletBinding()]param([Parameter()][string]$SourcePath,[Parameter()][string]$TargetPath)
    Add-Folders $TargetPath
    Add-Folders $(Split-Path $SourcePath -Parent)
    Log-Message "VRBS" "Creating $TargetPath(Actual) to $SourcePath(Link) symbolic link" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    try{cmd "/c" mklink "/J" $SourcePath $TargetPath; Log-Message "VRBS" "$TargetPath(Actual) to $SourcePath(Link) symbolic link created successfully" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
    catch{Log-Message "ERRR" "Unable to create $TargetPath symbolic link" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
    return $true
}

function Move-Folder {[CmdletBinding()]param([Parameter()][string]$InstallDir,[Parameter()][string]$Version="",[Parameter()][string]$Prefix="")
    $sourceDir = "${InstallDir}\${Prefix}${Version}"
    $destinationDir = $InstallDir
    Log-Message "VRBS" "Executing Move-Item from $sourceDir to $destinationDir" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    try{Get-ChildItem -Path $sourceDir | Move-Item -Destination $destinationDir -Force}
    catch{Log-Message "ERRR" "Unable to move $sourceDir to $destinationDir" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
    try{Remove-Item -Path $sourceDir -Recurse -Force}
    catch{Log-Message "ERRR" "Unable to remove $sourceDir" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
    return $true
}

function Get-SoftwareList {[CmdletBinding()]param([Parameter()][string]$DirPath,[Parameter()][string]$FileName)
    Log-Message "INFO" "Getting software list From: $DirPath\$FileName" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    $SoftwareListPath = "$DirPath\$FileName"
    if (-Not (Test-Path $SoftwareListPath)) {Log-Message "ERRR" "Software list JSON file not found at $SoftwareListPath" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $null}
    try{
        $SoftwareList = Get-Content -Raw -Path $SoftwareListPath | ConvertFrom-Json
        Log-Message "SCSS" "Software list successfully loaded" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
        return $SoftwareList
    }
    catch{Log-Message "ERRR" "Unable to load software list" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $null}
}

function Save-SoftwareListApplication {[CmdletBinding()]param([Parameter()][string]$DirPath,[Parameter()][string]$FileName,[Parameter()][object]$Application)
    Log-Message "INFO" "Saving software list to: $DirPath\$FileName" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    $SoftwareListPath = "$DirPath\$FileName"
    if (-Not (Test-Path $SoftwareListPath)) {Log-Message "ERRR" "Software list JSON file not found at $SoftwareListPath" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $null}
    try{
        $SoftwareList = Get-Content -Raw -Path $SoftwareListPath | ConvertFrom-Json
        $SoftwareList | Where-Object { $_.Name -eq $Application.Name -and $_.Version -eq $Application.Version } | ForEach-Object {
            Log-Message "DBUG" "SoftwareList: $($_ | ConvertTo-Json -Depth 10)" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
            Log-Message "DBUG" "Application: $($Application | ConvertTo-Json -Depth 10)" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
            $_.Download = $Application.Download
            $_.Install = $Application.Install
            $_.MachineScope = $Application.MachineScope
            $_.InstallationType = $Application.InstallationType
            $_.ApplicationID = $Application.ApplicationID
            $_.DownloadURL = $Application.DownloadURL
            $_.ProcessID = $Application.ProcessID
            $_.InstallerArguments = $Application.InstallerArguments
            $_.UninstallerArguments = $Application.UninstallerArguments
            # $_.Test_InstallPath = $Application.Test_InstallPath
            # $_.Test_MachineScope = $Application.Test_MachineScope
        }
        $SoftwareList | ConvertTo-Json -Depth 10 | Set-Content -Path $SoftwareListPath
        Log-Message "INFO" "Software list successfully updated and saved" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
        return $SoftwareList
    }catch{
        Log-Message "ERRR" "Unable to load software list" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
        Log-Message "DBUG" "Error: $_" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
        return $null
    }
}
#endregion
#region     APPLICATION HELPERS
function Install-Winget {[CmdletBinding()]param()
    if(-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Log-Message "INFO" "Installing WinGet PowerShell module from PSGallery..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
        Install-PackageProvider -Name NuGet -Force | Out-Null
        Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery | Out-Null
        Log-Message "INFO" "Using Repair-WinGetPackageManager cmdlet to bootstrap WinGet..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
        Repair-WinGetPackageManager
        Write-Progress -Completed -Activity "make progress bar dissapear"
        Log-Message "INFO" "Done." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    }
    return $true
}   

function Install-PSModule {[CmdletBinding()]param([Parameter()][string]$ModuleName,[Parameter()][string]$RepositoryName,[Parameter()][string]$Version,[Parameter()][bool]$WhatIfFlag=$false)
    Remove-PSModule -ModuleName $ModuleName -WhatIfFlag:$WhatIfFlag
    $installParams = @{Name=$ModuleName;Force=$true;Confirm=$false}
    if ($RepositoryName) {$installParams.Repository = $RepositoryName}
    if ($Version) {$installParams.RequiredVersion = $Version}
    Log-Message "INFO" "Installing $ModuleName"+(if($Version){" v$Version"}else{""})+(if($RepositoryName){" from $RepositoryName..."}else{"..."}) -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    try {Install-Module @installParams; Log-Message "INFO" "$ModuleName installed successfully" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
    catch {Log-Message "ERRR" "Unable to install $ModuleName" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
    return $true
}

function Remove-PSModule {[CmdletBinding()]param([Parameter()][string]$ModuleName,[Parameter()][bool]$WhatIfFlag=$false)
    $found = Get-Module -Name $ModuleName -ListAvailable
    if ($found.Count -gt 0){
        Log-Message "VRBS" "Previous versions found. Removing $($found.Count) versions of $ModuleName..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
        try{$found | Uninstall-Module -WhatIf:$WhatIfFlag; Log-Message "INFO" "Previous version removal completed successfully" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
        catch{Log-Message "ERRR" "Unable to remove previous version" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
        Get-Module -Name $ModuleName -ListAvailable
    }else{Log-Message "WARN" "No previous version of $ModuleName were found" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
    return $true
}
#endregion
#region     STEP HELPERS
function Invoke-MainPreStep {[CmdletBinding()]param()
    Log-Message "INFO" "Starting main pre-step..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    if (-not (Install-Winget)) {Log-Message "ERRR" "Failed to install WinGet" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
    $SoftwareList = Get-SoftwareList -DirPath $ScriptsDirectory -FileName $SoftwareListFileName
    if (-Not $SoftwareList) {Log-Message "ERRR" "No software found for specified environment and server type." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
    Log-Message "INFO" "Main pre-step complete" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    return $SoftwareList
}

function Invoke-MainInstallPreStep {[CmdletBinding()]param()
    Log-Message "INFO" "Starting main install pre-step..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    foreach ($dir in @($BinariesDirectory, $StagingDirectory, $PostInstallDirectory)) {
        if (-not (Add-Folders -DirPath $dir)) {Log-Message "ERRR" "Failed to add directory $dir" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose;return $false}
    }
    Log-Message "INFO" "Main install pre-step complete" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    return $true
}

function Invoke-MainUninstallPreStep {[CmdletBinding()]param()
    Log-Message "INFO" "Starting main uninstall pre-step..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    Log-Message "INFO" "Main uninstall pre-step complete" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    return $true
}

function Invoke-MainTestPreStep {[CmdletBinding()]param()
    Log-Message "INFO" "Starting main install pre-step..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    foreach ($dir in @($BinariesDirectory, $StagingDirectory, $PostInstallDirectory)) {
        if (-not (Add-Folders -DirPath $dir)) {Log-Message "ERRR" "Failed to add directory $dir" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose;return $false}
    }
    Log-Message "INFO" "Main install pre-step complete" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    return $true
}

function Invoke-MainPostStep {[CmdletBinding()]param()
    Log-Message "INFO" "Starting main post-step..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    Log-Message "INFO" "Main post-step complete" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    return $true
}

function Invoke-MainInstallPostStep {[CmdletBinding()]param()
    Log-Message "INFO" "Starting main install post-step..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    Log-Message "INFO" "Main install post-step complete" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    return $true
}

function Invoke-MainUninstallPostStep {[CmdletBinding()]param()
    Log-Message "INFO" "Starting main uninstall post-step..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    Log-Message "INFO" "Main uninstall post-step complete" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    return $true
}

function Invoke-MainTestPostStep {[CmdletBinding()]param()
    Log-Message "INFO" "Starting main uninstall post-step..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    Log-Message "INFO" "Main uninstall post-step complete" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    return $true
}

# Pre/Post steps helper function
function Invoke-ScriptStep {[CmdletBinding()]param([Parameter()][string]$StepName,[Parameter()][object]$Application)
    $StepResult = $true
    $Function = Get-Command -Name "Invoke-${StepName}_$($Application.Name)" -CommandType Function -ErrorAction SilentlyContinue
    if($Function) {
        Log-Message "INFO" "Starting $StepName for $($Application.Name) v$($Application.Version)..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
        $StepResult = & $Function -Application $Application
        if ($StepResult) {Log-Message "SCSS" "$StepName for $($Application.Name) v$($Application.Version) completed successfully" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
        else {Log-Message "ERRR" "$StepName for $($Application.Name) v$($Application.Version) failed" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
    }else{Log-Message "VRBS" "$StepName for $($Application.Name) v$($Application.Version) not defined" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
    return $StepResult
}
#endregion
#endregion
#region TESTING
function Invoke-Test_WingetInstallVersion {[CmdletBinding()]param([Parameter()][object]$Application)
    $versionList = Find-WinGetPackage -Id $Application.ApplicationID -MatchOption Equals | Select-Object -ExpandProperty AvailableVersions
    $versionList
    foreach ($version in $versionList) {
        Log-Message "INFO" "Attempting to install $($Application.Name) version $version..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
        $InstallArguments = @("--version",$version, "--accept-source-agreements","--accept-package-agreements","--silent","--force","--location", $Application.InstallPath)
        Invoke-Process -Path "winget" -Action "install" -Application @("--id",$Application.ApplicationID) -Arguments $InstallArguments
        if ((Test-Path $Application.InstallPath) -and (Get-ChildItem -Path $Application.InstallPath).Count -gt 0) {
            Log-Message "SCSS" "Successfully installed $($Application.Name) version $version at $($Application.InstallPath)" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
            $InstallArgumentsString = "--version;$version"
            if($Application.InstallerArguments -notlike "*$InstallArgumentsString*") {$Application.InstallerArguments = $Application.InstallerArguments + ";$InstallArgumentsString"}
            Save-SoftwareListApplication -DirPath $ScriptsDirectory -FileName $SoftwareListFileName -Application $Application
            $UninstallArguments = @("--silent","--force","--disable-interactivity","--ignore-warnings")
            Invoke-Process -Path "winget" -Action "uninstall" -Application @("--id",$Application.ApplicationID) -Arguments $UninstallArguments
            return $true
        } else {
            Log-Message "ERRR" "Installation of $($Application.Name) version $version failed. Retrying with previous version..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
            $UninstallArguments = @("--silent","--force","--disable-interactivity","--ignore-warnings")
            Invoke-Process -Path "winget" -Action "uninstall" -Application @("--id",$Application.ApplicationID) -Arguments $UninstallArguments
        }
    }
    Log-Message "ERRR" "All installation attempts for $($Application.Name) failed." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    return $false
}

function Invoke-Test_WingetInstallPath {[CmdletBinding()]param([Parameter()][object]$Application)
    $ReturnStatus=$true
    if($Application.Test_InstallPath) {
        $version = (Find-WinGetPackage -Id $Application.ApplicationID -MatchOption Equals).Version
        Log-Message "INFO" "Testing install path ($($Application.InstallPath)) of $($Application.Name) v$version using winget..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
        $BaseArguments = @("--accept-source-agreements","--accept-package-agreements","--silent","--force")
        $TestArguments = @("--custom","--override")
        $CustomAttributes = @("TARGETDIR","TARGETPATH","TARGETLOCATION","TARGETFOLDER","INSTALLDIR","INSTALLPATH","INSTALLLOCATION","INSTALLFOLDER","DIR","D")
        $CustomAttributePrefixes = @("","/","-","--")
        $CustomAttributeSeparators = @("=",":"," ")
        $CustomAttributeWrappers = @("","`"","'")
        $CustomValueWrappers = @("","`"","'")

        foreach ($CustomValueWrapper in $CustomValueWrappers) {
            $InstallArguments = $BaseArguments
            $InstallArguments += @("--location","$CustomValueWrapper$($Application.InstallPath)$CustomValueWrapper")
            Invoke-Process -Path "winget" -Action "install" -Application @("--id",$Application.ApplicationID) -Arguments $InstallArguments
            if ((Test-Path $Application.InstallPath) -and (Get-ChildItem -Path $Application.InstallPath).Count -gt 0) {
                Log-Message "SCSS" "Install path $($Application.InstallPath) validated successfully" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
                $InstallArgumentsString = ("--location;$CustomValueWrapper`$InstallPath$CustomValueWrapper").Replace('"','\"')
                if($Application.InstallerArguments -notlike "*$InstallArgumentsString*") {$Application.InstallerArguments = $Application.InstallerArguments + ";$InstallArgumentsString"}
                $ReturnStatus=$true
            }
            else {
                Log-Message "ERRR" "Install path $($Application.InstallPath) creation failed" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
                $ReturnStatus=$false
            }
            if($Application.ProcessID){Invoke-KillProcess $Application.ProcessID}
            $UninstallArguments = @("--silent","--force","--disable-interactivity","--ignore-warnings")
            Invoke-Process -Path "winget" -Action "uninstall" -Application @("--id",$Application.ApplicationID) -Arguments $UninstallArguments
            if($ReturnStatus) {break}
        }

    #     if(-not $ReturnStatus){
    #         foreach ($TestArg in $TestArguments) {
    #             foreach ($CustomAttribute in $CustomAttributes) {
    #                 foreach ($CustomAttributePrefix in $CustomAttributePrefixes) {
    #                     foreach ($CustomAttributeSeparator in $CustomAttributeSeparators) {
    #                         foreach ($CustomAttributeWrapper in $CustomAttributeWrappers) {
    #                             foreach ($CustomValueWrapper in $CustomValueWrappers) {
    #                                 $InstallArguments = $BaseArguments
    #                                 $InstallArguments += @("$TestArg","$CustomAttributeWrapper$CustomAttributePrefix$CustomAttribute$CustomAttributeSeparator$CustomValueWrapper$($Application.InstallPath)$CustomValueWrapper$CustomAttributeWrapper")
    #                                 Invoke-Process -Path "winget" -Action "install" -Application @("--id",$Application.ApplicationID) -Arguments $InstallArguments
    #                                 if ((Test-Path $Application.InstallPath) -and (Get-ChildItem -Path $Application.InstallPath).Count -gt 0) {
    #                                     Log-Message "SCSS" "Install path $($Application.InstallPath) created successfully" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    #                                     $InstallArgumentsString = ("--location;$CustomValueWrapper`$InstallPath$CustomValueWrapper").Replace('"','\"')
    #                                     if($Application.InstallerArguments -notlike "*$InstallArgumentsString*") {$Application.InstallerArguments = $Application.InstallerArguments + ";$InstallArgumentsString"}
    #                                     $ReturnStatus=$true
    #                                 }
    #                                 else {
    #                                     Log-Message "ERRR" "Install path $($Application.InstallPath) creation failed" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    #                                     $ReturnStatus=$false
    #                                 }
    #                                 if($Application.ProcessID){Invoke-KillProcess $Application.ProcessID}
    #                                 $UninstallArguments = @("--silent","--force","--disable-interactivity","--ignore-warnings")
    #                                 Invoke-Process -Path "winget" -Action "uninstall" -Application @("--id",$Application.ApplicationID) -Arguments $UninstallArguments
    #                                 if($ReturnStatus) {break}
    #                             }
    #                         }
    #                     }
    #                 }
    #             }
    #         }
    #     }

        $Application.Test_InstallPath=$false
        Save-SoftwareListApplication -DirPath $ScriptsDirectory -FileName $SoftwareListFileName -Application $Application
    }
    return $ReturnStatus
}

function Invoke-Test_WingetMachineScope {[CmdletBinding()]param([Parameter()][object]$Application)
    $ReturnStatus = $true
    if($Application.Test_MachineScope) {
        $version = (Find-WinGetPackage -Id $Application.ApplicationID -MatchOption Equals).Version
        Log-Message "INFO" "Testing machine scope installation of $($Application.Name) v$version using winget..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
        $BaseArguments = @("--accept-source-agreements","--accept-package-agreements","--silent","--force","--location",$Application.InstallPath)
        $TestArguments = @("--scope","machine")

        $InstallArguments = $BaseArguments + $TestArguments
        $Process = Invoke-Process -Path "winget" -Action "install" -Application @("--id",$Application.ApplicationID) -Arguments $InstallArguments
        $Process.ExitCode
        if ($Process.ExitCode -eq 0) {
            Log-Message "SCSS" "$($Application.Name) installed with machine scope successfully" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
            $Application.MachineScope=$true
            $ReturnStatus = $true
        }
        else {
            Log-Message "ERRR" "Machine scope installation of $($Application.Name) failed" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
            $Application.MachineScope=$false
            $ReturnStatus = $false
        }
        $Application.Test_MachineScope=$false
        Save-SoftwareListApplication -DirPath $ScriptsDirectory -FileName $SoftwareListFileName -Application $Application
        if($Application.ProcessID){Invoke-KillProcess $Application.ProcessID}
        $UninstallArguments = @("--silent","--force","--disable-interactivity","--ignore-warnings")
        Invoke-Process -Path "winget" -Action "uninstall" -Application @("--id",$Application.ApplicationID) -Arguments $UninstallArguments
    }
    return $ReturnStatus
}

function Invoke-Testing {[CmdletBinding()]param([Parameter()][object]$Application)
    Log-Message "INFO" "Beginning testing of $($Application.Name) v$($Application.Version)..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    if($Application.InstallationType -eq "Winget") {
        if(-not (Invoke-Test_WingetMachineScope -Application $Application)) {Log-Message "ERRR" "Winget machine scope testing failed" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
        if(-not (Invoke-Test_WingetInstallPath -Application $Application)) {Log-Message "ERRR" "Winget install path testing failed" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
    }
    return $true
}
#endregion
#region DOWNLOAD
function Invoke-DownloadSoftware {[CmdletBinding()]param([Parameter()][object]$Application)
    if($Application.Download) {
        Invoke-ScriptStep -StepName "PreDownload" -Application $Application
        if ($Application.InstallationType -eq "Winget") {
            $TempBinaryPath = $($Application.BinaryPath).Replace([System.IO.Path]::GetExtension($Application.BinaryPath), "")
            Log-Message "INFO" "Downloading $($Application.Name) version $($Application.Version) from winget to $TempBinaryPath..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
            Add-Folders -DirPath $TempBinaryPath
            $version = (Find-WinGetPackage -Id $Application.ApplicationID -MatchOption Equals).Version
            $DownloadArguments = @("--version",$version,"--download-directory", "`"$TempBinaryPath`"","--accept-source-agreements","--accept-package-agreements")
            if ($Application.MachineScope) {$DownloadArguments += @("--scope","machine")}
            try {
                $Process = Invoke-Process -Path "winget" -Action "download" -Application @("--id",$Application.ApplicationID) -Arguments $DownloadArguments
                if ($Process.ExitCode -eq 0 -or $null -eq $Process.ExitCode) {
                    Log-Message "SCSS" "$($Application.Name) v$version downloaded successfully" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
                } else {
                    $errorMessage = $process.StandardError.ReadToEnd()
                    Log-Message "ERRR" "$($Application.Name) download failed with exit code $($process.ExitCode). Error: $errorMessage" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
                    return $false
                }
            }
            catch{Log-Message "ERRR" "Unable to download $($Application.Name) using winget" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; Log-Message "DBUG" "Error: $($_.Exception.Message)" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
            $files = Get-ChildItem -Path $TempBinaryPath
            foreach ($file in $files) {
                $NewFileName = if($file.PSIsContainer) {"$($Application.Name)_$($Application.Version)_$($file.Name)"}
                else{"$($Application.Name)_$($Application.Version)$($file.Extension)"}
                $destinationPath = Join-Path -Path $BinariesDirectory -ChildPath $NewFileName
                Log-Message "VRBS" "Moving file $($file.FullName) to $destinationPath" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
                try {
                    Move-Item -Path $file.FullName -Destination $destinationPath -Force
                    Log-Message "VRBS" "Moved $($file.Name) to $destinationPath" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
                } catch {Log-Message "ERRR" "Failed to move $($file.Name) to $destinationPath. Error: $($_.Exception.Message)" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
            }
            # Remove the application binary path after moving files
            try {
                Remove-Item -Path $TempBinaryPath -Recurse -Force
                Log-Message "VRBS" "Removed application binary path: $TempBinaryPath" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
            } catch {Log-Message "ERRR" "Failed to remove application binary path: $TempBinaryPath. Error: $($_.Exception.Message)" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
        } else {
            Log-Message "VRBS" "Checking for $($Application.Name) version $($Application.Version) in $($Application.BinaryPath)..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
            if (-not (Test-Path $($Application.BinaryPath))) {
                Log-Message "INFO" "Downloading $($Application.Name) version $($Application.Version) from $($Application.DownloadURL) to $($Application.BinaryPath)..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
                Log-Message "VRBS" "Executing Invoke-WebRequest for $($Application.DownloadURL) to $($Application.BinaryPath)" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
                try {
                    Invoke-WebRequest -Uri $Application.DownloadURL -OutFile $($Application.BinaryPath)
                    Log-Message "SCSS" "Download of $($Application.Name) v$($Application.Version) completed successfully" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
                }
                catch {Log-Message "ERRR" "Execution of Invoke-WebRequest for $($Application.DownloadURL) to $($Application.BinaryPath) unsuccessful" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose;return $false}
            } else {Log-Message "WARN" "$($Application.Name) v$($Application.Version) already exists in $($Application.BinaryPath)" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
        }
        Log-Message "VRBS" "Copying from $($Application.BinaryPath) to $($Application.StagedPath)" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
        if(Test-Path $($Application.BinaryPath)) {
            try {Copy-Item -Path $($Application.BinaryPath) -Destination $($Application.StagedPath) -Force}
            catch {Log-Message "ERRR" "Unable to copy from $($Application.BinaryPath) to $($Application.StagedPath)" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose;return $false}
        }
        Invoke-ScriptStep -StepName "PostDownload" -Application $Application
    } else {Log-Message "VRBS" "Download flag for $($Application.Name) v$($Application.Version) set to false" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
    return $true
}
#endregion
#region INSTALL
function Invoke-InstallSoftware {[CmdletBinding()]param([Parameter()][object]$Application)
    if($Application.Install) {
        if (-not (Invoke-ScriptStep -StepName "PreInstall" -Application $Application)) {Log-Message "ERRR" "Pre-install step failed" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
        if($Application.SymLinkPath){Add-SymLink -SourcePath $Application.SymLinkPath -TargetPath $Application.InstallPath}
        # Log-Message "INFO" "Starting installation of $($Application.Name) v$($Application.Version)..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
        if ($Application.InstallationType -eq "Winget") {
            $version = (Find-WinGetPackage -Id $Application.ApplicationID -MatchOption Equals).Version
            Log-Message "INFO" "Installing $($Application.Name) v$version from winget..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
            $FileName   = Get-LogFileName -LogType "Transcript" -Action 'Install' -TargetName $Application.Name -Version $version
            $FilePath   = Join-Path -Path $LogDirectory -ChildPath $FileName
            $BaseArguments = @("--accept-source-agreements","--accept-package-agreements","--force","--log",$FilePath)
            $ApplicationArguments = if($Application.Download -and (Test-Path -Path $($Application.BinaryPath).Replace([System.IO.Path]::GetExtension($Application.BinaryPath),".yaml"))) {
                @("--manifest",$($Application.BinaryPath).Replace([System.IO.Path]::GetExtension($Application.BinaryPath),".yaml"))
            } else {@("--id",$Application.ApplicationID)}
            $InstallArguments = $BaseArguments
            if ($Application.InstallerArguments) {$InstallArguments += $Application.InstallerArguments}
            try {
                $Process = Invoke-Process -Path "winget" -Action "install" -Application $ApplicationArguments -Arguments $InstallArguments
                if ($Process.ExitCode -eq 0 -or $null -eq $Process.ExitCode) {
                    Log-Message "SCSS" "$($Application.Name) v$version installed successfully" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
                } else {
                    Log-Message "ERRR" "$($Application.Name) installation failed with exit code $($Process.ExitCode)" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
                    return $false
                }
            }
            catch{Log-Message "ERRR" "Unable to install $($Application.Name) using winget" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; Log-Message "DBUG" "Error: $($_.Exception.Message)" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
        } elseif ($Application.InstallationType -eq "PSModule") {
            Install-PSModule -ModuleName $Application.ModuleID
        } else {
            $FileType = [System.IO.Path]::GetExtension($Application.StagedPath)
            switch ($FileType) {
                ".zip" {
                    Log-Message "INFO" "Extracting ZIP file for $($Application.Name) v$($Application.Version) to $($Application.InstallPath)..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
                    Log-Message "DBUG" "Executing Expand-Archive -Path $($Application.StagedPath) -DestinationPath $($Application.InstallPath) -Force" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
                    try{
                        Expand-Archive -Path $Application.StagedPath -DestinationPath $Application.InstallPath -Force
                        Log-Message "SCSS" "$($Application.Name) v$version extracted successfully" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
                    }
                    catch{Log-Message "ERRR" "Extraction of $($Application.StagedPath) to $($Application.InstallPath) failed" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
                }
                ".msi" {
                    Log-Message "INFO" "Running MSI installer for $($Application.Name) v$($Application.Version)..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
                    try{
                        $BaseArguments = @("/passive","/norestart")
                        $InstallArguments = $Application.InstallArguments + $BaseArguments
                        Invoke-Process -Path "msiexec.exe" -Action "/i" -Application @("`"$($Application.StagedPath)`"") -Arguments $InstallArguments -Wait
                        Log-Message "SCSS" "$($Application.Name) v$version installed successfully" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
                    }
                    catch{Log-Message "ERRR" "Installation of $($Application.Name) v$($Application.Version) failed" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
                }
                ".exe" {
                    Log-Message "INFO" "Running installer for $($Application.Name) v$($Application.Version)..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
                    try{
                        $Process = Invoke-Process -Path $Application.StagedPath -Arguments $Application.InstallerArguments
                        if ($Process.ExitCode -eq 0 -or $null -eq $Process.ExitCode) {
                                    Log-Message "SCSS" "$($Application.Name) v$version installed successfully" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
                        } else {
                            Log-Message "ERRR" "$($Application.Name) installation failed with exit code $($Process.ExitCode)" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
                            return $false
                        }
                        # Log-Message "SCSS" "$($Application.Name) v$version installed successfully" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
                    }
                    catch{Log-Message "ERRR" "Installation of $($Application.Name) v$($Application.Version) failed" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
                }
            }
        }
        if($Application.ProcessIDs){foreach($Process in $Application.ProcessIDs){Invoke-KillProcess $Process}}
        Invoke-ScriptStep -StepName "PostInstall" -Application $Application
        if(-not((Test-Path $Application.InstallPath) -and (Get-ChildItem -Path $Application.InstallPath).Count -gt 0)) {
            Log-Message "WARN" "Validation of InstallPath ($($Application.InstallPath)) failed for $($Application.Name) v$($Application.Version)" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
        }
    } else {Log-Message "VRBS" "Install flag for $($Application.Name) v$($Application.Version) set to false" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
    if(Test-Path $($Application.StagedPath)) {
        Log-Message "VRBS" "Executing Move-Item from $($Application.StagedPath) to $($Application.PostInstallPath)" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
        try{Move-Item -Path $Application.StagedPath -Destination $Application.PostInstallPath -Force}
        catch{Log-Message "ERRR" "Unable to move item from $($Application.StagedPath) to $($Application.PostInstallPath)" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
    }
    return $true
}
#endregion
#region UNINSTALL
# Function to uninstall software
function Invoke-UninstallSoftware {[CmdletBinding()]param([Parameter()][object]$Application)
    Log-Message "INFO" "Starting uninstallation of $($Application.Name) v$($Application.Version)..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    if (-not (Invoke-ScriptStep -StepName "PreUninstall" -Application $Application)) {Log-Message "ERRR" "Pre-uninstall step failed" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
    $FileType = [System.IO.Path]::GetExtension($Application.PostInstallPath)
    switch ($FileType) {
        ".msi" {
            Log-Message "INFO" "Running MSI uninstaller for $($Application.Name) v$($Application.Version)..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
            $Command = "msiexec.exe /x $PostInstallDirectory/$($Application.Name)_$($Application.Version)$FileType /qb!"
            Log-Message "DBUG" "Executing command: $Command" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
            try{
                Start-Process -FilePath "msiexec.exe" -ArgumentList "/x $PostInstallDirectory/$($Application.Name)_$($Application.Version)$FileType /qb!" -Wait
                Log-Message "SCSS" "$($Application.Name) v$version uninstalled successfully" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
            }
            catch{Log-Message "ERRR" "Command execution unsuccessful: $Command" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
        }
        ".exe" {
            Log-Message "INFO" "Running uninstaller for $($Application.Name) v$($Application.Version)..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
            $UninstallerArguments = $Application.UninstallerArguments
            $Command = "$($Application.PostInstallPath) $UninstallerArguments"
            Log-Message "DBUG" "Executing command: $Command" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
            if($Application.PostInstallPath){
                try{
                    Start-Process -FilePath $Application.PostInstallPath -ArgumentList $UninstallerArguments -Wait
                    Log-Message "SCSS" "$($Application.Name) v$version uninstalled successfully" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
                }
                catch{Log-Message "ERRR" "Command execution unsuccessful: $Command" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
            }
        }
        default {
            if($Application.InstallPath -and (Test-Path -Path $Application.InstallPath)){
                Log-Message "INFO" "Deleting files for $($Application.Name) v$($Application.Version) in $($Application.InstallPath)..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
                try{Remove-Item -Path $Application.InstallPath -Recurse -Force;Log-Message "SCSS" "Deleting files for $($Application.Name) v$($Application.Version) in $($Application.InstallPath) completed successfully" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
                catch{Log-Message "ERRR" "Unable to remove from $($Application.InstallPath)" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
            }
        }
    }
    Invoke-ScriptStep -StepName "PostUninstall" -Application $Application
    if($Application.InstallPath -and (Test-Path -Path $Application.InstallPath)){
        Log-Message "INFO" "Deleting files for $($Application.Name) v$($Application.Version) in $($Application.InstallPath)..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
        try{Remove-Item -Path $Application.InstallPath -Recurse -Force;Log-Message "SCSS" "Deleting files for $($Application.Name) v$($Application.Version) in $($Application.InstallPath) completed successfully" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
        catch{Log-Message "ERRR" "Unable to remove from $($Application.InstallPath)" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
    }
    return $true
}
#endregion
#region MAIN
function Invoke-MainAction {[CmdletBinding()]param([Parameter()][object]$SoftwareList)
    if ($Action -eq "Install") {
        if (-not (Invoke-MainInstallPreStep)) {Log-Message "ERRR" "Pre-install step failed" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
        foreach ($Application in $SoftwareList) {
            if($TestingMode -and $Application.TestingComplete) {continue}
            if ($ApplicationName -and ($Application.Name -ne $ApplicationName -or ($ApplicationVersion -and $Application.Version -ne $ApplicationVersion))) {continue}
            Log-Message "PROG" "---------- Processing installation for $($Application.Name) v$($Application.Version) ----------" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
            $InstallProcessStart = Get-Date
            $FileExtension = [System.IO.Path]::GetExtension($Application.DownloadURL)
            if([string]::IsNullOrEmpty($FileExtension) -or $FileExtension.Length -gt 5) {$FileExtension = ".exe"}
            $AppName = "$($Application.Name)_$($Application.Version)$FileExtension"
            $nameParts = if ($Application.Name -like "*_*") { $Application.Name -split "_" } else { @($Application.Name) }
            $installPath = if ($nameParts.Count -gt 1) { "$InstallDirectory\$($nameParts[0])\$($nameParts[1])" } else { "$InstallDirectory\$($Application.Name)" }
            $Application | Add-Member -MemberType NoteProperty -Name "InstallPath" -Value $installPath -Force
            $Application | Add-Member -MemberType NoteProperty -Name "BinaryPath" -Value "${BinariesDirectory}\${AppName}" -Force
            $Application | Add-Member -MemberType NoteProperty -Name "StagedPath" -Value "${StagingDirectory}\${AppName}" -Force
            $Application | Add-Member -MemberType NoteProperty -Name "PostInstallPath" -Value "${PostInstallDirectory}\${AppName}" -Force
            $Replacements = @{'$Name'=$Application.Name;'$Version'=$Application.Version;'$StagedPath'=$Application.StagedPath;'$InstallPath'=$Application.InstallPath;'$BinariesDirectory'=$BinariesDirectory;'$StagingDirectory'=$StagingDirectory}
            if($Application.InstallerArguments){$Application.InstallerArguments = $($Application.InstallerArguments).ForEach{$Argument=$_;$($Replacements.GetEnumerator()).ForEach{$Argument = $Argument.Replace($_.Key, $_.Value)};$Argument}}
            if (-not (Invoke-DownloadSoftware -Application $Application)) {Log-Message "ERRR" "Download failed" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
            if (-not (Invoke-InstallSoftware -Application $Application)) {Log-Message "ERRR" "Installation failed" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
            $InstallProcessEnd = Get-Date
            $InstallProcessTimeSpan = New-TimeSpan -Start $InstallProcessStart -End $InstallProcessEnd
            Log-Message "PROG" $("---------- Installation processing of $($Application.Name) v$($Application.Version) completed in {0:00}:{1:00}:{2:00}:{3:00} ----------" -f $InstallProcessTimeSpan.days,$InstallProcessTimeSpan.hours,$InstallProcessTimeSpan.minutes,$InstallProcessTimeSpan.seconds) -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
        }
        Invoke-MainInstallPostStep
    } elseif ($Action -eq "Uninstall") {
        Invoke-MainUninstallPreStep
        [Array]::Reverse($SoftwareList)
        foreach ($Application in $SoftwareList) {
            if($TestingMode -and $Application.TestingComplete) {continue}
            if ($ApplicationName -and ($Application.Name -ne $ApplicationName -or ($ApplicationVersion -and $Application.Version -ne $ApplicationVersion))) {continue}
            Log-Message "PROG" "---------- Processing uninstallation for $($Application.Name) v$($Application.Version) ----------" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
            $UninstallProcessStart = Get-Date
            $Application | Add-Member -MemberType NoteProperty -Name "PostInstallPath" -Value "$($PostInstallDirectory)\$($Application.Name)_$($Application.Version)$([System.IO.Path]::GetExtension($Application.BinaryURI))"
            $Replacements = @{'$Name'=$Application.Name;'$Version'=$Application.Version;'$StagedPath'=$Application.StagedPath;'$InstallPath'=$Application.InstallPath;'$BinariesDirectory'=$BinariesDirectory;'$StagingDirectory'=$StagingDirectory}
            if($Application.UninstallerArguments){$Application.UninstallerArguments = $($Application.UninstallerArguments).ForEach{$Argument=$_;$($Replacements.GetEnumerator()).ForEach{$Argument = $Argument.Replace($_.Key, $_.Value)};$Argument}}
            if (-not (Invoke-UninstallSoftware -Application $Application)) {Log-Message "ERRR" "Uninstallation failed" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
            $UninstallProcessEnd = Get-Date
            $UninstallProcessTimeSpan = New-TimeSpan -Start $UninstallProcessStart -End $UninstallProcessEnd
            Log-Message "PROG" $("---------- Uninstallation processing of $($Application.Name) v$($Application.Version) completed in {0:00}:{1:00}:{2:00}:{3:00} ----------" -f $UninstallProcessTimeSpan.days,$UninstallProcessTimeSpan.hours,$UninstallProcessTimeSpan.minutes,$UninstallProcessTimeSpan.seconds) -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
        }
        Invoke-MainUninstallPostStep
    } elseif ($Action -eq "Test") {
        Invoke-MainTestPreStep
        foreach ($Application in $SoftwareList) {
            if($TestingMode -and $Application.TestingComplete) {continue}
            if ($ApplicationName -and ($Application.Name -ne $ApplicationName -or ($ApplicationVersion -and $Application.Version -ne $ApplicationVersion))) {continue}
            Log-Message "INFO" "---------- Processing testing for $($Application.Name) v$($Application.Version) ----------" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
            $FileExtension = [System.IO.Path]::GetExtension($Application.DownloadURL)
            if([string]::IsNullOrEmpty($FileExtension) -or $FileExtension.Length -gt 5) {$FileExtension = ".exe"}
            $AppName = "$($Application.Name)_$($Application.Version)$FileExtension"
            $nameParts = if ($Application.Name -like "*_*") { $Application.Name -split "_" } else { @($Application.Name) }
            $installPath = if ($nameParts.Count -gt 1) { "$InstallDirectory\$($nameParts[0])\$($nameParts[1])" } else { "$InstallDirectory\$($Application.Name)" }
            $Application | Add-Member -MemberType NoteProperty -Name "InstallPath" -Value $installPath -Force
            $Application | Add-Member -MemberType NoteProperty -Name "BinaryPath" -Value "${BinariesDirectory}\${AppName}" -Force
            $Application | Add-Member -MemberType NoteProperty -Name "StagedPath" -Value "${StagingDirectory}\${AppName}" -Force
            $Application | Add-Member -MemberType NoteProperty -Name "PostInstallPath" -Value "${PostInstallDirectory}\${AppName}" -Force
            $Replacements = @{'$Name'=$Application.Name;'$Version'=$Application.Version;'$StagedPath'=$Application.StagedPath;'$InstallPath'=$Application.InstallPath;'$BinariesDirectory'=$BinariesDirectory;'$StagingDirectory'=$StagingDirectory}
            # if($Application.InstallerArguments){$Application.InstallerArguments = $($Application.InstallerArguments).ForEach{$Argument=$_;$($Replacements.GetEnumerator()).ForEach{$Argument = $Argument.Replace($_.Key, $_.Value)};$Argument}}
            # if($Application.UninstallerArguments){$Application.UninstallerArguments = $($Application.UninstallerArguments).ForEach{$Argument=$_;$($Replacements.GetEnumerator()).ForEach{$Argument = $Argument.Replace($_.Key, $_.Value)};$Argument}}
            if (-not (Invoke-Testing -Application $Application)) {Log-Message "ERRR" "Testing failed" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
        }
        Invoke-MainTestPostStep
    } else {Log-Message "ERRR" "Invalid action specified. Use 'Install', 'Uninstall', or 'Test'." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
}

if (-Not (Test-Path -Path $LogDirectory)) {New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null}
$HostName   = hostname
$Version    = $PSVersionTable.PSVersion.ToString()
$FileName   = Get-LogFileName -LogType "Transcript" -Action $Action -TargetName $HostName -Version $Version
$FilePath   = Join-Path -Path $LogDirectory -ChildPath $FileName
Start-Transcript -IncludeInvocationHeader -NoClobber -Path $FilePath
if ($PSBoundParameters['Debug']) {$DebugPreference = 'Continue'}
$ScriptStart = Get-Date
Set-Location -Path $ScriptsDirectory

Log-Message "PROG" "Beginning main script execution..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
$SoftwareList = Invoke-MainPreStep
. "$PSScriptRoot/Personal_ToolSetup_AppSpecific.ps1"
$WingetSoftwareList = $SoftwareList | Where-Object {$_.InstallationType -eq "Winget"}
$PSModuleSoftwareList = $SoftwareList | Where-Object {$_.InstallationType -eq "PSModule"}
$OtherSoftwareList = $SoftwareList | Where-Object {$_.InstallationType -eq "Other"}
$ManualSoftwareList = $SoftwareList | Where-Object {$_.InstallationType -eq "Manual"}
Invoke-MainAction -SoftwareList $WingetSoftwareList
Invoke-MainAction -SoftwareList $PSModuleSoftwareList
Invoke-MainAction -SoftwareList $OtherSoftwareList
Invoke-MainAction -SoftwareList $ManualSoftwareList
Invoke-MainPostStep

$ScriptEnd = Get-Date
$ScriptTimeSpan = New-TimeSpan -Start $ScriptStart -End $ScriptEnd
Log-Message "PROG" $("Main script execution completed in {0:00}:{1:00}:{2:00}:{3:00}" -f $ScriptTimeSpan.days,$ScriptTimeSpan.hours,$ScriptTimeSpan.minutes,$ScriptTimeSpan.seconds) -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
Stop-Transcript | Out-Null
#endregion