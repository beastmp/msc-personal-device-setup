
#region PREDOWNLOAD
# Pre-Download function template: Add _$Application.Name to the end of the function name
function Invoke-PreDownload {[CmdletBinding()]param([Parameter()][object]$Application)
    return $true
}
#endregion
#region POSTDOWNLOAD
# Post-Download function template: Add _$Application.Name to the end of the function name
function Invoke-PostDownload {[CmdletBinding()]param([Parameter()][object]$Application)
    return $true
}
function Invoke-PostDownload_Cookn {[CmdletBinding()]param([Parameter()][object]$Application)
    Start-Sleep -Seconds 30
    return $true
}

function Invoke-PostDownload_DiskDigger {[CmdletBinding()]param([Parameter()][object]$Application)
    if (-not (Add-Folders -DirPath $Application.InstallPath)) {Log-Message "ERRR" "Failed to add install path" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
    Log-Message "VRBS" "Executing Copy-Item from $($Application.StagedPath) to $($Application.InstallPath)\$($Application.Name)$([System.IO.Path]::GetExtension($Application.BinaryPath))" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    try{Copy-Item -Path $Application.StagedPath -Destination "$($Application.InstallPath)\$($Application.Name)$([System.IO.Path]::GetExtension($Application.BinaryPath))" -Force}
    catch{Log-Message "ERRR" "Unable to copy from $($Application.StagedPath) to $($Application.InstallPath)\$($Application.Name)$([System.IO.Path]::GetExtension($Application.BinaryPath))" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
    return $true
}

function Invoke-PostDownload_NuGet {[CmdletBinding()]param([Parameter()][object]$Application)
    if (-not (Add-Folders -DirPath $Application.InstallPath)) {Log-Message "ERRR" "Failed to add install path" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
    Log-Message "INFO" "Starting Post-Download for $($Application.Name) v$($Application.Version)..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    if (-not (Add-Folders -DirPath $Application.InstallPath)) {Log-Message "ERRR" "Failed to add install path" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
    Log-Message "VRBS" "Executing Copy-Item from $($Application.StagedPath) to $($Application.InstallPath)\$($Application.Name)$([System.IO.Path]::GetExtension($Application.BinaryPath))" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    try{Copy-Item -Path $Application.StagedPath -Destination "$($Application.InstallPath)\$($Application.Name)$([System.IO.Path]::GetExtension($Application.BinaryPath))" -Force}
    catch{Log-Message "ERRR" "Unable to copy from $($Application.StagedPath) to $($Application.InstallPath)\$($Application.Name)$([System.IO.Path]::GetExtension($Application.BinaryPath))" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}

    if (-not (Set-EnvironmentVariable -Name "NUGET_HOME" -Value $Application.InstallPath)) {Log-Message "ERRR" "Failed to set NUGET_HOME" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
    if (-not (Add-ToPath -Value $Application.InstallPath)) {Log-Message "ERRR" "Failed to add to PATH" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine")

    return $true
}

function Invoke-PostDownload_MSI_CommandCenter {[CmdletBinding()]param([Parameter()][object]$Application)
    Remove-Item -Path $Application.StagedPath -Force
    Log-Message "INFO" "Extracting ZIP file for $($Application.Name) v$($Application.Version) to $StagingDirectory..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    Log-Message "DBUG" "Executing Expand-Archive -Path $($Application.BinaryPath) -DestinationPath $StagingDirectory -Force" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    try{
        $FolderName = Expand-Archive -Path $Application.BinaryPath -DestinationPath $StagingDirectory -Verbose -Force *>&1  | Foreach-Object {
            if($_.message -match "Created '(.*\.exe)'.*"){Get-Item $Matches[1]}
        }
        Log-Message "SCSS" "$($Application.Name) v$($Application.Version) extracted successfully" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    }
    catch{Log-Message "ERRR" "Extraction of $($Application.BinaryPath) to $StagingDirectory failed" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
    $Application.StagedPath = "$StagingDirectory\$($Application.Name)_$($Application.Version).exe"
    Move-Item -Path $FolderName -Destination $Application.StagedPath -Force
    Remove-Item -Path $FolderName.Directory -Recurse -Force
    return $true
}

function Invoke-PostDownload_MSI_LiveUpdate {[CmdletBinding()]param([Parameter()][object]$Application)
    Remove-Item -Path $Application.StagedPath -Force
    Log-Message "INFO" "Extracting ZIP file for $($Application.Name) v$($Application.Version) to $StagingDirectory..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    Log-Message "DBUG" "Executing Expand-Archive -Path $($Application.BinaryPath) -DestinationPath $StagingDirectory -Force" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    try{
        $FolderName = Expand-Archive -Path $Application.BinaryPath -DestinationPath $StagingDirectory -Verbose -Force *>&1  | Foreach-Object {
            if($_.message -match "Created '(.*\.exe)'.*"){Get-Item $Matches[1]}
        }
        Log-Message "SCSS" "$($Application.Name) v$($Application.Version) extracted successfully" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    }
    catch{Log-Message "ERRR" "Extraction of $($Application.BinaryPath) to $StagingDirectory failed" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
    $Application.StagedPath = "$StagingDirectory\$($Application.Name)_$($Application.Version).exe"
    Move-Item -Path $FolderName -Destination $Application.StagedPath -Force
    Remove-Item -Path $FolderName.Directory -Recurse -Force
    return $true
}

function Invoke-PostDownload_Git {[CmdletBinding()]param([Parameter()][object]$Application)
    $GitOptions = """
[Setup]
Lang=default
Dir=$($Application.InstallPath)
Group=Git
NoIcons=0
SetupType=default
Components=ext,ext\shellhere,ext\guihere,gitlfs,assoc,assoc_sh,autoupdate,windowsterminal,scalar
Tasks=
EditorOption=VisualStudioCode
CustomEditorPath=
DefaultBranchOption=main
PathOption=Cmd
SSHOption=OpenSSH
TortoiseOption=false
CURLOption=OpenSSL
CRLFOption=CRLFAlways
BashTerminalOption=ConHost
GitPullBehaviorOption=Merge
UseCredentialManager=Enabled
PerformanceTweaksFSCache=Enabled
EnableSymlinks=Disabled
EnableFSMonitor=Disabled
"""
    $GitOptions | Set-Content -Path "$BinariesDirectory\$($Application.Name)_$($Application.Version).ini"
    return $true
}
#endregion
#region PREINSTALL
# Pre-Install function template: Add _$Application.Name to the end of the function name
function Invoke-PreInstall {[CmdletBinding()]param([Parameter()][object]$Application)
    return $true
}

function Invoke-PreInstall_Adobe_Acrobat {[CmdletBinding()]param([Parameter()][object]$Application)
    $Application.InstallPath = $Application.InstallPath.Replace("\Acrobat","")
    Add-Folders $Application.InstallPath
    $Application.InstallerArguments = $($Application.InstallerArguments).ForEach{$_.Replace("\Acrobat","")}
    return $true
}
#endregion
#region POSTINSTALL
# Post-Install function template: Add _$Application.Name to the end of the function name
function Invoke-PostInstall {[CmdletBinding()]param([Parameter()][object]$Application)
    return $true
}

function Invoke-PostInstall_Python {[CmdletBinding()]param([Parameter()][object]$Application)
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User") 

    Log-Message "VRBS" "Upgrading pip..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    $Command = "python -m pip install --upgrade pip"
    Log-Message "DBUG" "Executing command: $Command" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    try {python -m pip install --upgrade pip;Log-Message "VRBS" "pip upgraded..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose}
    catch {Log-Message "ERRR" "Failed to upgrade pip" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
    return $true
}

function Invoke-PostInstall_Seagate_DiskWizard {[CmdletBinding()]param([Parameter()][object]$Application)
    $ApplicationPath = (Get-ChildItem -Path $Application.InstallPath).FullName
    Log-Message "INFO" "Running installer for $($Application.Name) v$($Application.Version)..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    try{
        Invoke-Process -Path $ApplicationPath -Arguments $Application.InstallerArguments
        Log-Message "SCSS" "$($Application.Name) v$version installed successfully" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    }
    catch{Log-Message "ERRR" "Installation of $($Application.Name) v$($Application.Version) unsuccessful" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose; return $false}
    return $true
}

function Invoke-PostInstall_Microsoft_VSCode {[CmdletBinding()]param([Parameter()][object]$Application)
    code --install-extension ms-vscode.powershell
    code --install-extension ms-dotnettools.csdevkit
    code --install-extension ms-mssql.mssql
    code --install-extension ms-azuretools.vscode-docker
    code --install-extension github.vscode-pull-request-github
    code --install-extension github.remotehub
    code --install-extension github.vscode-github-actions
    code --install-extension github.codespaces
    code --install-extension golang.go
    code --install-extension ms-python.python
    code --install-extension hashicorp.terraform
    return $true
}
#endregion
#region PREUNINSTALL
# Pre-Uninstall function template: Add _$Application.Name to the end of the function name
function Invoke-PreUninstall {[CmdletBinding()]param([Parameter()][object]$Application)
    return $true
}
#endregion
#region POSTUNINSTALL
# Post-Uninstall function template: Add _$Application.Name to the end of the function name
function Invoke-PostUninstall {[CmdletBinding()]param([Parameter()][object]$Application)
    return $true
}
#endregion