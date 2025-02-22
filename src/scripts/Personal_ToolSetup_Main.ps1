#region PARAMS
[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [ValidateScript({Test-Path $_})]
    [string]$ConfigPath = "$(Split-Path -Parent $PSScriptRoot)/config/script_config.json",
    
    [Parameter(Mandatory=$false)]
    [ValidateSet("Install","Uninstall","Test")]
    [string]$Action = "Install",
    
    [Parameter(Mandatory=$false)]
    [string]$ApplicationName,
    
    [Parameter(Mandatory=$false)]
    [string]$ApplicationVersion,
    
    [switch]$TestingMode,
    [switch]$ParallelDownloads,
    [switch]$CleanupCache
)

# Resolve module paths and import modules
$modulePath = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $modulePath "modules"
Write-Host "Module path resolved to: $modulePath"

# Import modules in dependency order with full paths
$moduleOrder = @(
        @{Name="ConfigManager"; Path=Join-Path $modulePath "ConfigManager.psm1"},
    @{Name="SystemOperations"; Path=Join-Path $modulePath "SystemOperations.psm1"},
    @{Name="Monitoring"; Path=Join-Path $modulePath "Monitoring.psm1"},
    @{Name="StateManager"; Path=Join-Path $modulePath "StateManager.psm1"},
    @{Name="ApplicationManager"; Path=Join-Path $modulePath "ApplicationManager.psm1"}
)

# Load all modules first
foreach ($module in $moduleOrder) {
    Write-Host "Loading module: $($module.Name) from $($module.Path)"
    if (Test-Path $module.Path) {
        Import-Module $module.Path -Force -Verbose
    } else {
        throw "Module file not found: $($module.Path)"
    }
}

# Initialize managers
try {
    # Create logger first with no paths
    $logger = New-LogManager
    $logger.Log("INFO", "Basic logger created")
    
    # Create config manager with logger
    $configManager = New-ConfigManager -ConfigPath $ConfigPath -Logger $logger
    $logger.Log("INFO", "ConfigManager initialized successfully")
    
    # Now initialize logger with proper paths
    $logger.Initialize(
        (Join-Path $configManager.ResolvePath('logs') "application.log"),
        (Join-Path $configManager.ResolvePath('logs') "telemetry.log")
    )
    $logger.Log("INFO", "Logger fully initialized with proper paths")
    
    # Initialize remaining managers with logger
    $stateManager = New-StateManager -StateFile $configManager.GetStatePath() -Logger $logger
    $logger.Log("INFO", "StateManager initialized successfully")
    
    $systemOps = New-SystemOperations -BinDir $configManager.ResolvePath("binaries") `
                                    -StagingDir $configManager.ResolvePath("staging") `
                                    -InstallDir $configManager.ResolvePath("install") `
                                    -Logger $logger
    $logger.Log("INFO", "SystemOperations initialized successfully")
    
    $appManager = New-ApplicationManager -SystemOps $systemOps `
                                       -StateManager $stateManager `
                                       -Logger $logger `
                                       -ConfigManager $configManager
    $logger.Log("INFO", "ApplicationManager initialized successfully")
}
catch {
    if ($logger) {
        $logger.Log("ERRR", "Failed to initialize managers: $_")
    }
    else {
        Write-Error "Failed to initialize managers: $_"
    }
    throw
}

# Load and validate configuration
try {
    $script:Config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
    $requiredProps = @('directories', 'files', 'logging')
    $missingProps = $requiredProps | Where-Object {-not $Config.PSObject.Properties.Name.Contains($_)}
    if ($missingProps) {throw "Missing required configuration properties: $($missingProps -join ', ')"} 
} catch {throw "Failed to load configuration from ${ConfigPath}: $_"}

$script:BinariesDirectory = $Config.directories.binaries
$script:ScriptsDirectory = $Config.directories.scripts
$script:StagingDirectory = $Config.directories.staging
$script:InstallDirectory = $Config.directories.install
$script:PostInstallDirectory = $Config.directories.postInstall
$script:LogDirectory = $Config.directories.logs
$script:SoftwareListFileName = $Config.files.softwareList

# Add cleanup on script exit
#trap {Write-Error $_;exit 1}

#region HELPERS
#region     LOG HELPERS
function Get-LogFileName {param([Parameter()][ValidateSet("Log","Transcript")][string]$LogType,[Parameter()][string]$Action,[Parameter()][string]$TargetName,[Parameter()][string]$Version)
    $ScriptName = $(Split-Path $MyInvocation.PSCommandPath -Leaf).Replace(".ps1", "")
    $DateTime   = Get-Date -f 'yyyyMMddHHmmss'
    $FileName   = $Config.logging.fileNameFormat.Replace("{LogType}", $LogType).Replace("{ScriptName}", $ScriptName).Replace("{Action}", $Action).Replace("{TargetName}", $TargetName).Replace("{Version}", $Version).Replace("{DateTime}", $DateTime)
    return $FileName
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
    Log-Message "INFO" "Starting main uninstall pre-step..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
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
    # return $true
}

function Invoke-MainInstallPostStep {[CmdletBinding()]param()
    Log-Message "INFO" "Starting main install post-step..." -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    Log-Message "INFO" "Main install post-step complete" -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
    # return $true
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

function Invoke-WithRetry {[CmdletBinding()]param([Parameter(Mandatory)][scriptblock]$ScriptBlock,[string]$Activity,[int]$MaxAttempts = $MaxRetries,[int]$DelaySeconds = $RetryDelay)
    $attempt = 1
    $success = $false
    while(-not $success -and $attempt -le $MaxAttempts){
        try {
            if($attempt -gt 1){Log-Message "WARN" "Retrying $Activity (Attempt $attempt of $MaxAttempts)..."}
            $result = & $ScriptBlock
            $success = $true
            return $result
        } catch {
            if($attempt -eq $MaxAttempts){Log-Message "ERRR" "Failed to $Activity after $MaxAttempts attempts: $_";throw}
            Log-Message "WARN" "Attempt $attempt failed: $_"
            Start-Sleep -Seconds $DelaySeconds
            $attempt++
        }
    }
}

function Start-ParallelDownloads {[CmdletBinding()]param([Parameter()][object[]]$Applications)
    $jobs = @()
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $MaxConcurrentJobs)
    $runspacePool.Open()
    
    foreach ($app in $Applications) {
        if (-not (Test-ApplicationDependencies -Application $app)) {
            Log-Message "ERRR" "Skipping $($app.Name) due to missing dependencies"
            continue
        }
        
        $powerShell = [powershell]::Create().AddScript({param($Application)
            Invoke-DownloadSoftware -Application $Application
        }).AddArgument($app)
        
        $powerShell.RunspacePool = $runspacePool
        
        $jobs += @{PowerShell = $powerShell;Handle = $powerShell.BeginInvoke();App = $app;StartTime = Get-Date}
    }
    
    # Wait for jobs with timeout
    while ($jobs.Where({ -not $_.Handle.IsCompleted })) {
        foreach ($job in $jobs.Where({ -not $_.Handle.IsCompleted })) {
            if ((Get-Date) - $job.StartTime -gt [TimeSpan]::FromSeconds($JobTimeout)) {
                Log-Message "ERRR" "Download timeout for $($job.App.Name)"
                $job.PowerShell.Stop()
                $job.Handle.IsCompleted = $true
            }
        }
        Start-Sleep -Seconds 1
    }
    
    foreach ($job in $jobs) {
        try {$job.PowerShell.EndInvoke($job.Handle)}
        catch {Log-Message "ERRR" "Error in parallel download of $($job.App.Name): $_"}
        finally {$job.PowerShell.Dispose()}
    }
    
    $runspacePool.Close()
    $runspacePool.Dispose()
}

# Add hash validation for downloads
function Test-FileHash {[CmdletBinding()]param([Parameter(Mandatory)][string]$FilePath,[Parameter(Mandatory)][string]$ExpectedHash,[string]$Algorithm = 'SHA256')
    $actualHash = (Get-FileHash -Path $FilePath -Algorithm $Algorithm).Hash
    return $actualHash -eq $ExpectedHash
}

function Remove-OldCache {
    [CmdletBinding()]
    param()
    
    $cacheFiles = Get-ChildItem -Path $BinariesDirectory -Filter "*.cache"
    $cutoffDate = (Get-Date).AddDays(-$CacheRetentionDays)
    
    foreach ($file in $cacheFiles) {
        $cacheContent = Get-Content $file.FullName | ConvertFrom-Json
        $cacheDate = [DateTime]::Parse($cacheContent.DateTime)
        if ($cacheDate -lt $cutoffDate) {
            Remove-Item $file.FullName -Force
            $binaryPath = $file.FullName.Replace(".cache", "")
            if (Test-Path $binaryPath) {
                Remove-Item $binaryPath -Force
            }
        }
    }
}

function Test-ApplicationDependencies {
    [CmdletBinding()]
    param([Parameter()][object]$Application)
    
    if (-not $Application.Dependencies) { return $true }
    
    foreach ($dep in $Application.Dependencies) {
        if ($dep.Type -eq "Application") {
            $installed = Test-Path $dep.InstallPath
            if (-not $installed) {
                Log-Message "ERRR" "Dependency $($dep.Name) not found at $($dep.InstallPath)"
                return $false
            }
        }
        elseif ($dep.Type -eq "WindowsFeature") {
            $feature = Get-WindowsOptionalFeature -Online -FeatureName $dep.Name
            if ($feature.State -ne "Enabled") {
                Log-Message "ERRR" "Required Windows feature $($dep.Name) is not enabled"
                return $false
            }
        }
    }
    return $true
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
    if(-not $Application.Download) { return $true }
    # Implement file caching
    $cacheKey = "$($Application.Name)_$($Application.Version)"
    $cachePath = Join-Path $BinariesDirectory "$cacheKey.cache"
    
    if (Test-Path $cachePath) {
        $cached = Get-Content $cachePath | ConvertFrom-Json
        if ($cached.Hash -and (Test-FileHash -FilePath $Application.BinaryPath -ExpectedHash $cached.Hash)) {
            Log-Message "INFO" "Using cached version of $($Application.Name) v$($Application.Version)"
            return $true
        }
    }
    
    Invoke-WithRetry -Activity "download $($Application.Name)" -ScriptBlock {
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
    }
    
    # Cache the download info
    $hash=(Get-FileHash -Path $Application.BinaryPath).Hash
    @{Hash=$hash;DateTime=Get-Date -Format "o"} | ConvertTo-Json | Set-Content $cachePath
    
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
#region MAIN
function Invoke-MainAction {[CmdletBinding()]param([Parameter()][object]$SoftwareList)
    switch ($Action) {
        "Install" {
            if (-not (Invoke-MainInstallPreStep)) { return $false }
            
            if ($ParallelDownloads) {
                $downloadJobs = @()
                foreach ($app in $SoftwareList) {
                    if (ShouldProcessApp $app) {
                        try {
                            $appManager.InitializeApplication($app)
                            $downloadJobs += Start-Job -ScriptBlock {
                                param($app)
                                $appManager.Download($app)
                            } -ArgumentList $app
                        }
                        catch {
                            $logger.Log("ERRR", "Failed to initialize $($app.Name): $_")
                            continue
                        }
                    }
                }
                Wait-Job $downloadJobs | Receive-Job
            }
            
            foreach ($app in $SoftwareList) {
                if (-not (ShouldProcessApp $app)) { continue }
                
                $logger.Log("PROG", "Processing installation for $($app.Name)")
                $timer = [System.Diagnostics.Stopwatch]::StartNew()
                
                try {
                    $app = $appManager.InitializeApplication($app)
                    
                    if (-not $ParallelDownloads) {
                        if (-not $appManager.Download($app)) { 
                            $logger.Log("ERRR", "Download failed for $($app.Name)")
                            continue 
                        }
                    }
                    
                    if (-not $appManager.Install($app)) {
                        $logger.Log("ERRR", "Installation failed for $($app.Name)")
                        continue
                    }
                    
                    $timer.Stop()
                    $logger.Log("PROG", "Installation of $($app.Name) completed in $($timer.Elapsed)")
                }
                catch {
                    $logger.Log("ERRR", "Failed to process $($app.Name): $_")
                    continue
                }
            }
            
            Invoke-MainInstallPostStep
        }
        
        "Uninstall" {
            if (-not (Invoke-MainUninstallPreStep)) { return $false }
            
            [Array]::Reverse($SoftwareList)
            foreach ($app in $SoftwareList) {
                if (-not (ShouldProcessApp $app)) { continue }
                
                $logger.Log("PROG", "Processing uninstallation for $($app.Name)")
                if (-not $appManager.Uninstall($app)) {
                    $logger.Log("ERRR", "Uninstallation failed for $($app.Name)")
                    continue
                }
            }
            
            Invoke-MainUninstallPostStep
        }
        
        "Test" {
            if (-not (Invoke-MainTestPreStep)) { return $false }
            
            foreach ($app in $SoftwareList) {
                if (-not (ShouldProcessApp $app)) { continue }
                
                $logger.Log("INFO", "Testing $($app.Name)")
                Invoke-Testing -Application $app
            }
            
            Invoke-MainTestPostStep
        }
    }
}

# Helper function to determine if an app should be processed
function ShouldProcessApp {
    param([Parameter()][object]$app)
    
    if ($TestingMode -and $app.TestingComplete) { return $false }
    if ($ApplicationName -and ($app.Name -ne $ApplicationName -or 
        ($ApplicationVersion -and $app.Version -ne $ApplicationVersion))) {
        return $false
    }
    return $true
}

if ($CleanupCache) {
    Remove-OldCache
}

if (-Not (Test-Path -Path $LogDirectory)) {New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null}
$HostName   = hostname
$Version    = $PSVersionTable.PSVersion.ToString()
$FileName   = Get-LogFileName -LogType "Transcript" -Action $Action -TargetName $HostName -Version $Version
$FilePath   = Join-Path -Path $LogDirectory -ChildPath $FileName
Start-Transcript -IncludeInvocationHeader -NoClobber -Path $FilePath
if ($PSBoundParameters['Debug']) {$DebugPreference = 'Continue'}
$ScriptStart = Get-Date
# Set-Location -Path $ScriptsDirectory

try {
    Log-Message "PROG" "Beginning main script execution..."
    $logger.TrackEvent("ScriptStart", @{
        Action = $Action
        TestingMode = $TestingMode
    })
    
    $SoftwareList = Invoke-MainPreStep
    
    # Process software by installation type - Fix the loop structure
    foreach ($installType in @('Winget', 'PSModule', 'Other', 'Manual')) {
        $currentType = $installType
        $logger.Log("INFO", "Processing $currentType applications")
        
        $typeList = $SoftwareList | Where-Object { $_.InstallationType -eq $currentType }
        
        if ($typeList) {
            $logger.Log("INFO", "Found $($typeList.Count) $currentType applications to process")
            Invoke-MainAction -SoftwareList $typeList
        } else {
                $logger.Log("INFO", "No $currentType applications found")
            }
        }
        
        Invoke-MainPostStep
        
        $logger.TrackEvent("ScriptEnd", @{
            Success = $true
            Duration = $ScriptTimeSpan.TotalSeconds
        })
    }
catch {
    $logger.TrackEvent("ScriptError", @{
        Error = $_.Exception.Message
        Stack = $_.ScriptStackTrace
    })
    throw
}
finally {
    $stateManager.CleanupOldStates(30)
    if (Test-Path $StagingDirectory) {
        Remove-Item -Path $StagingDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$ScriptEnd = Get-Date
$ScriptTimeSpan = New-TimeSpan -Start $ScriptStart -End $ScriptEnd
Log-Message "PROG" $("Main script execution completed in {0:00}:{1:00}:{2:00}:{3:00}" -f $ScriptTimeSpan.days,$ScriptTimeSpan.hours,$ScriptTimeSpan.minutes,$ScriptTimeSpan.seconds) -Debug:$PSBoundParameters.Debug -Verbose:$PSBoundParameters.Verbose
Stop-Transcript | Out-Null
#endregion