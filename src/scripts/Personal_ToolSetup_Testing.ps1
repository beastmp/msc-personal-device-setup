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

