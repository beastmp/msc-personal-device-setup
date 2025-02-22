<#
.SYNOPSIS
    Custom installation handlers for specific applications.
#>

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
    if (-not (Add-Folders -DirPath $Application.InstallPath)) {$logger.Log("ERRR", "Failed to add install path"); return $false}
    $logger.Log("VRBS", "Executing Copy-Item from $($Application.StagedPath) to $($Application.InstallPath)\$($Application.Name)$([System.IO.Path]::GetExtension($Application.BinaryPath))")
    try{Copy-Item -Path $Application.StagedPath -Destination "$($Application.InstallPath)\$($Application.Name)$([System.IO.Path]::GetExtension($Application.BinaryPath))" -Force}
    catch{$logger.Log("ERRR","Unable to copy from $($Application.StagedPath) to $($Application.InstallPath)\$($Application.Name)$([System.IO.Path]::GetExtension($Application.BinaryPath))"); return $false}
    return $true
}

function Invoke-PostDownload_NuGet {[CmdletBinding()]param([Parameter()][object]$Application)
    if (-not ($systemOps.AddFolders($Application.InstallPath))) {$logger.Log("ERRR", "Failed to add install path");return $false}
    $logger.Log("VRBS", "Executing Copy-Item from $($Application.StagedPath) to $($Application.InstallPath)\$($Application.Name)$([System.IO.Path]::GetExtension($Application.BinaryPath))")
    try{Copy-Item -Path $Application.StagedPath -Destination "$($Application.InstallPath)\$($Application.Name)$([System.IO.Path]::GetExtension($Application.BinaryPath))" -Force}
    $systemOps.SetEnvironmentVariable("NUGET_HOME",$Application.InstallPath)
    $systemOps.AddToPath($Application.InstallPath)
    return $true
}

function Invoke-PostDownload_MSI_CommandCenter {[CmdletBinding()]param([Parameter()][object]$Application)
    Remove-Item -Path $Application.StagedPath -Force
    $logger.Log("INFO", "Extracting ZIP file for $($Application.Name) v$($Application.Version) to $StagingDirectory...")
    $logger.Log("DBUG", "Executing Expand-Archive -Path $($Application.BinaryPath) -DestinationPath $StagingDirectory -Force")
    $FolderName = Expand-Archive -Path $Application.BinaryPath -DestinationPath $StagingDirectory -Verbose -Force *>&1  | Foreach-Object {
        if($_.message -match "Created '(.*\.exe)'.*"){Get-Item $Matches[1]}
    }
    $logger.Log("SCSS", "$($Application.Name) v$($Application.Version) extracted successfully")
    $Application.StagedPath = "$StagingDirectory\$($Application.Name)_$($Application.Version).exe"
    $logger.Log("VRBS", "Executing Move-Item from $FolderName to $Application.StagedPath")
    Move-Item -Path $FolderName -Destination $Application.StagedPath -Force
    Remove-Item -Path $FolderName.Directory -Recurse -Force
    return $true
}

function Invoke-PostDownload_MSI_LiveUpdate {[CmdletBinding()]param([Parameter()][object]$Application)
    Remove-Item -Path $Application.StagedPath -Force
    $logger.Log("INFO", "Extracting ZIP file for $($Application.Name) v$($Application.Version) to $StagingDirectory...")
    $logger.Log("DBUG", "Executing Expand-Archive -Path $($Application.BinaryPath) -DestinationPath $StagingDirectory -Force")
    $FolderName = Expand-Archive -Path $Application.BinaryPath -DestinationPath $StagingDirectory -Verbose -Force *>&1  | Foreach-Object {
        if($_.message -match "Created '(.*\.exe)'.*"){Get-Item $Matches[1]}
    }
    $logger.Log("SCSS", "$($Application.Name) v$($Application.Version) extracted successfully")
    $Application.StagedPath = "$StagingDirectory\$($Application.Name)_$($Application.Version).exe"
    $logger.Log("VRBS", "Executing Move-Item from $FolderName to $Application.StagedPath")
    Move-Item -Path $FolderName -Destination $Application.StagedPath -Force
    Remove-Item -Path $FolderName.Directory -Recurse -Force
    $logger.Log("INFO", "Post-Download completed for $($Application.Name)")
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
    $systemOps.AddFolders($Application.InstallPath)
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
    $logger.Log("VRBS", "Upgrading pip...")
    $systemOps.StartProcess("python",@("-m","pip","install","--upgrade","pip"))
    $logger.Log("VRBS", "pip upgraded...")
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