using namespace System.Collections
using namespace System.IO

class ApplicationConfig {
    [string]$Name
    [string]$Version
    [string]$InstallationType
    [string]$ApplicationID
    [string]$ModuleID
    [string]$DownloadURL
    [string[]]$ProcessIDs
    [string[]]$InstallerArguments
    [string[]]$UninstallerArguments
    [bool]$Download
    [bool]$Install
    [bool]$MachineScope
    [string]$InstallPath
    [string]$BinaryPath
    [string]$StagedPath
    [string]$PostInstallPath
    [string]$SymLinkPath
    [Dependency[]]$Dependencies
    [bool]$TestingComplete
}

class Dependency {
    [string]$Type
    [string]$Name
    [string]$InstallPath
    [Version]$MinVersion
}

class InstallationState {
    [string]$Status
    [datetime]$StartTime
    [datetime]$EndTime
    [string]$ErrorMessage
    [hashtable]$Metadata = @{}
}

Export-ModuleMember -Function @()
