function Log-Message {[CmdletBinding()]param([Parameter()][ValidateSet("INFO","SCSS","ERRR","WARN","DBUG","VRBS","PROG")][string]$LogLevel="INFO",[Parameter()][string]$Message)
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $color = switch ($LogLevel) {"SCSS"{"Green"}"ERRR"{"Red"}"WARN"{"Yellow"}"DBUG"{"Cyan"}"VRBS"{"DarkYellow"}"PROG"{"Magenta"}default{"White"}}
    if ($LogLevel -eq "DBUG" -and -not ($PSBoundParameters.Debug -eq $true)) {return}
    if ($LogLevel -eq "VRBS" -and -not ($PSBoundParameters.Verbose -eq $true)) {return}
    Write-Host "[$timestamp] [$LogLevel] $Message" -ForegroundColor $color
}

function Add-Folders {[CmdletBinding()]param([Parameter()][string]$DirPath)
    if (-Not (Test-Path -Path $DirPath)) {
        try{New-Item -ItemType Directory -Path $DirPath -Force | Out-Null; Log-Message "VRBS" "$DirPath directory created successfully" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
        catch{Log-Message "ERRR" "Unable to create $DirPath directory" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
    }
    return $true
}

function Add-SymLink {[CmdletBinding()]param([Parameter()][string]$SourcePath,[Parameter()][string]$TargetPath)
    Remove-Item $SourcePath -Force
    Remove-Item $TargetPath -Force
    Add-Folders $TargetPath
    Add-Folders $(Split-Path $SourcePath -Parent)
    Log-Message "VRBS" "Creating $TargetPath(Actual) to $SourcePath(Link) symbolic link" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    try{cmd "/c" mklink "/J" $SourcePath $TargetPath; Log-Message "VRBS" "$TargetPath(Actual) to $SourcePath(Link) symbolic link created successfully" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
    catch{Log-Message "ERRR" "Unable to create $TargetPath symbolic link" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
    return $true
}

$Application = '{
    "Name": "Google_Chrome",
    "Version": "latest",
    "Download": true,
    "Install": true,
    "MachineScope": false,
    "InstallationType": "Winget",
    "WingetID": "Google.Chrome",
    "DownloadURL": "",
    "ProcessIDs": [],
    "InstallerArguments": [],
    "UninstallerArguments": [],
    "WingetInstallerArguments": [],
    "WingetUninstallerArguments": [],
    "SymLinkPath": "C:\\Program Files\\Google\\Chrome"
  }' | ConvertFrom-Json

$BinariesDirectory = "C:\Testing\Binaries"
$ScriptsDirectory = "C:\Temp\Scripts"
$StagingDirectory = "C:\Testing\Staging"
$InstallDirectory = "C:\Testing\Apps"
$PostInstallDirectory = "C:\Testing\Installed"
$LogDirectory = "C:\Testing\Logs"

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
if($Application.WingetInstallerArguments){$Application.WingetInstallerArguments = $($Application.WingetInstallerArguments).ForEach{$Argument=$_;$($Replacements.GetEnumerator()).ForEach{$Argument = $Argument.Replace($_.Key, $_.Value)};$Argument}}

if($Application.SymLinkPath){Add-SymLink -SourcePath $Application.SymLinkPath -TargetPath $Application.InstallPath}

function Invoke-Test_WingetInstallVersion {[CmdletBinding()]param([Parameter()][object]$Application)
    $versionList = Find-WinGetPackage -Id $Application.ApplicationID -MatchOption Equals | Select-Object -ExpandProperty AvailableVersions
    $versionList
    foreach ($version in $versionList) {
        $logger.Log("INFO","Attempting to install $($Application.Name) version $version...")
        $InstallArguments = @("--version",$version, "--accept-source-agreements","--accept-package-agreements","--silent","--force","--location", $Application.InstallPath)
        Invoke-Process -Path "winget" -Action "install" -Application @("--id",$Application.ApplicationID) -Arguments $InstallArguments
        if ((Test-Path $Application.InstallPath) -and (Get-ChildItem -Path $Application.InstallPath).Count -gt 0) {
            $logger.Log("SCSS","Successfully installed $($Application.Name) version $version at $($Application.InstallPath)")
            $InstallArgumentsString = "--version;$version"
            if($Application.InstallerArguments -notlike "*$InstallArgumentsString*") {$Application.InstallerArguments = $Application.InstallerArguments + ";$InstallArgumentsString"}
            $configManager.SaveSoftwareListApplication($ScriptsDirectory, $SoftwareListFileName, $Application)
            $UninstallArguments = @("--silent","--force","--disable-interactivity","--ignore-warnings")
            Invoke-Process -Path "winget" -Action "uninstall" -Application @("--id",$Application.ApplicationID) -Arguments $UninstallArguments
            return $true
        } else {
            $logger.Log("ERRR","Installation of $($Application.Name) version $version failed. Retrying with previous version...")
            $UninstallArguments = @("--silent","--force","--disable-interactivity","--ignore-warnings")
            Invoke-Process -Path "winget" -Action "uninstall" -Application @("--id",$Application.ApplicationID) -Arguments $UninstallArguments
        }
    }
    $logger.Log("ERRR","All installation attempts for $($Application.Name) failed.")
    return $false
}

function Invoke-Test_WingetInstallPath {[CmdletBinding()]param([Parameter()][object]$Application)
    $ReturnStatus=$true
    if($Application.Test_InstallPath) {
        $version = (Find-WinGetPackage -Id $Application.ApplicationID -MatchOption Equals).Version
        $logger.Log("INFO","Testing install path ($($Application.InstallPath)) of $($Application.Name) v$version using winget...")
        $BaseArguments = @("--accept-source-agreements","--accept-package-agreements","--silent","--force")
        $TestArguments = @("--custom","--override")
        $CustomAttributes = @("TARGETDIR","TARGETPATH","TARGETLOCATION","TARGETFOLDER","INSTALLDIR","INSTALLPATH","INSTALLLOCATION","INSTALLFOLDER","DIR","D")
        $CustomAttributePrefixes = @("","/","-","--")
        $CustomAttributeSeparators = @("="," ",":")
        $CustomAttributeWrappers = @("","`"","'")
        $CustomValueWrappers = @("","`"","'")

        foreach ($CustomValueWrapper in $CustomValueWrappers) {
            $InstallArguments = $BaseArguments
            $InstallArguments += @("--location","$CustomValueWrapper$($Application.InstallPath)$CustomValueWrapper")
            Invoke-Process -Path "winget" -Action "install" -Application @("--id",$Application.ApplicationID) -Arguments $InstallArguments
            if ((Test-Path $Application.InstallPath) -and (Get-ChildItem -Path $Application.InstallPath).Count -gt 0) {
                $logger.Log("SCSS","Install path $($Application.InstallPath) validated successfully")
                $InstallArgumentsString = ("--location;$CustomValueWrapper`$InstallPath$CustomValueWrapper").Replace('"','\"')
                if($Application.InstallerArguments -notlike "*$InstallArgumentsString*") {$Application.InstallerArguments = $Application.InstallerArguments + ";$InstallArgumentsString"}
                $ReturnStatus=$true
            }
            else {
                $logger.Log("ERRR","Install path $($Application.InstallPath) creation failed")
                $ReturnStatus=$false
            }
            if($Application.ProcessID){Invoke-KillProcess $Application.ProcessID}
            $UninstallArguments = @("--silent","--force","--disable-interactivity","--ignore-warnings")
            Invoke-Process -Path "winget" -Action "uninstall" -Application @("--id",$Application.ApplicationID) -Arguments $UninstallArguments
            if($ReturnStatus) {break}
        }

        if(-not $ReturnStatus){
            foreach ($TestArg in $TestArguments) {
                foreach ($CustomAttribute in $CustomAttributes) {
                    foreach ($CustomAttributePrefix in $CustomAttributePrefixes) {
                        foreach ($CustomAttributeSeparator in $CustomAttributeSeparators) {
                            foreach ($CustomAttributeWrapper in $CustomAttributeWrappers) {
                                foreach ($CustomValueWrapper in $CustomValueWrappers) {
                                    $InstallArguments = $BaseArguments
                                    $InstallArguments += @("$TestArg","$CustomAttributeWrapper$CustomAttributePrefix$CustomAttribute$CustomAttributeSeparator$CustomValueWrapper$($Application.InstallPath)$CustomValueWrapper$CustomAttributeWrapper")
                                    Invoke-Process -Path "winget" -Action "install" -Application @("--id",$Application.ApplicationID) -Arguments $InstallArguments
                                    if ((Test-Path $Application.InstallPath) -and (Get-ChildItem -Path $Application.InstallPath).Count -gt 0) {
                                        $logger.Log("SCSS","Install path $($Application.InstallPath) created successfully")
                                        $InstallArgumentsString = ("--location;$CustomValueWrapper`$InstallPath$CustomValueWrapper").Replace('"','\"')
                                        if($Application.InstallerArguments -notlike "*$InstallArgumentsString*") {$Application.InstallerArguments = $Application.InstallerArguments + ";$InstallArgumentsString"}
                                        $ReturnStatus=$true
                                    }
                                    else {
                                        $logger.Log("ERRR","Install path $($Application.InstallPath) creation failed")
                                        $ReturnStatus=$false
                                    }
                                    if($Application.ProcessID){Invoke-KillProcess $Application.ProcessID}
                                    $UninstallArguments = @("--silent","--force","--disable-interactivity","--ignore-warnings")
                                    Invoke-Process -Path "winget" -Action "uninstall" -Application @("--id",$Application.ApplicationID) -Arguments $UninstallArguments
                                    if($ReturnStatus) {break}
                                }
                            }
                        }
                    }
                }
            }
        }

        $Application.Test_InstallPath=$false
        $configManager.SaveSoftwareListApplication($ScriptsDirectory, $SoftwareListFileName, $Application)
    }
    return $ReturnStatus
}

function Invoke-Test_WingetMachineScope {[CmdletBinding()]param([Parameter()][object]$Application)
    $ReturnStatus = $true
    if($Application.Test_MachineScope) {
        $version = (Find-WinGetPackage -Id $Application.ApplicationID -MatchOption Equals).Version
        $logger.Log("INFO","Testing machine scope installation of $($Application.Name) v$version using winget...")
        $BaseArguments = @("--accept-source-agreements","--accept-package-agreements","--silent","--force","--location",$Application.InstallPath)
        $TestArguments = @("--scope","machine")

        $InstallArguments = $BaseArguments + $TestArguments
        $Process = Invoke-Process -Path "winget" -Action "install" -Application @("--id",$Application.ApplicationID) -Arguments $InstallArguments
        $Process.ExitCode
        if ($Process.ExitCode -eq 0) {
            $logger.Log("SCSS","$($Application.Name) installed with machine scope successfully")
            $Application.MachineScope=$true
            $ReturnStatus = $true
        }
        else {
            $logger.Log("ERRR","Machine scope installation of $($Application.Name) failed")
            $Application.MachineScope=$false
            $ReturnStatus = $false
        }
        $Application.Test_MachineScope=$false
        $configManager.SaveSoftwareListApplication($ScriptsDirectory, $SoftwareListFileName, $Application)
        if($Application.ProcessID){Invoke-KillProcess $Application.ProcessID}
        $UninstallArguments = @("--silent","--force","--disable-interactivity","--ignore-warnings")
        Invoke-Process -Path "winget" -Action "uninstall" -Application @("--id",$Application.ApplicationID) -Arguments $UninstallArguments
    }
    return $ReturnStatus
}

function Invoke-Testing {[CmdletBinding()]param([Parameter()][object]$Application)
    $logger.Log("INFO","Beginning testing of $($Application.Name) v$($Application.Version)...")
    if($Application.InstallationType -eq "Winget") {
        if(-not (Invoke-Test_WingetMachineScope -Application $Application)) {$logger.Log("ERRR","Winget machine scope testing failed"); return $false}
        if(-not (Invoke-Test_WingetInstallPath -Application $Application)) {$logger.Log("ERRR","Winget install path testing failed"); return $false}
    }
    return $true
}