<#
.SYNOPSIS
    Main installation script for personal device setup.
.DESCRIPTION
    Manages installation, uninstallation, and testing of applications using various package managers.
#>

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
    [switch]$CleanupCache
)
#endregion

$modulePath = Split-Path -Parent $PSScriptRoot
$modulePath = Join-Path $modulePath "modules"
if ($PSBoundParameters['Verbose']) {Write-Host "[$(Get-Date -f 'yyyyMMdd_HHmmss')] [VRBS] Module path resolved to: $modulePath" -ForegroundColor "DarkYellow"}
$moduleOrder = @(
    @{Name="ConfigManager"; Path=Join-Path $modulePath "ConfigManager.psm1"},
    @{Name="SystemOperations"; Path=Join-Path $modulePath "SystemOperations.psm1"},
    @{Name="Monitoring"; Path=Join-Path $modulePath "Monitoring.psm1"},
    @{Name="ApplicationManager"; Path=Join-Path $modulePath "ApplicationManager.psm1"}
)
foreach ($module in $moduleOrder) {
    if ($PSBoundParameters['Verbose']) {Write-Host "[$(Get-Date -f 'yyyyMMdd_HHmmss')] [VRBS] Loading module: $($module.Name) from $($module.Path)" -ForegroundColor "DarkYellow"}
    if (Test-Path $module.Path) {Import-Module $module.Path -Force 4> $null}
    else {Write-Host "[$(Get-Date -f 'yyyyMMddHHmmss')] [ERRR] Module file not found: $($module.Path)" -ForegroundColor "Red";throw}
}
try {
    $logger = New-LogManager
    $logger.Log("VRBS", "Basic logger created")
    
    $configManager = New-ConfigManager -ConfigPath $ConfigPath -Logger $logger
    $logger.Log("VRBS", "ConfigManager initialized successfully")
    
    $logger.Initialize(
        (Join-Path $configManager.ResolvePath('logs') "application.log"),
        (Join-Path $configManager.ResolvePath('logs') "telemetry.log")
    )
    $logger.Log("VRBS", "Logger fully initialized with proper paths")
    
    $systemOps = New-SystemOperations -BinDir $configManager.ResolvePath("binaries") `
                                    -StagingDir $configManager.ResolvePath("staging") `
                                    -InstallDir $configManager.ResolvePath("install") `
                                    -Logger $logger `
                                    -Config $configManager.Config
    $logger.Log("VRBS", "SystemOperations initialized successfully")
    
    $appManager = New-ApplicationManager -SystemOps $systemOps `
                                       -Logger $logger `
                                       -ConfigManager $configManager
    $logger.Log("VRBS", "ApplicationManager initialized successfully")
}
catch {if($logger){$logger.Log("ERRR", "Failed to initialize managers: $_")}else{Write-Error "Failed to initialize managers: $_"};throw}
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

#trap {Write-Error $_;exit 1}

#region TESTING
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
    #                                     $logger.Log("SCSS","Install path $($Application.InstallPath) created successfully")
    #                                     $InstallArgumentsString = ("--location;$CustomValueWrapper`$InstallPath$CustomValueWrapper").Replace('"','\"')
    #                                     if($Application.InstallerArguments -notlike "*$InstallArgumentsString*") {$Application.InstallerArguments = $Application.InstallerArguments + ";$InstallArgumentsString"}
    #                                     $ReturnStatus=$true
    #                                 }
    #                                 else {
    #                                     $logger.Log("ERRR","Install path $($Application.InstallPath) creation failed")
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
#endregion
#region MAIN
function Invoke-MainAction {
    [CmdletBinding()]
    param([Parameter()][object]$SoftwareList)
    
    switch ($Action) {
        "Install" {
            $preSuccess = $appManager.InvokeStep("Main","Pre","Install")
            if (-not $preSuccess) {$this.Logger.Log("WARN", "Main PreInstall step failed. Proceeding with app installation...")}
            
            foreach ($app in $SoftwareList) {
                if (-not (ShouldProcessApp $app)) { continue }
                
                $logger.Log("PROG", "Processing installation for $($app.Name)")
                $timer = [System.Diagnostics.Stopwatch]::StartNew()
                
                try {
                    $app = $appManager.InitializeApplication($app)
                    if (-not $appManager.DownloadAll($SoftwareList, $ParallelDownloads)) {
                        $logger.Log("ERRR", "Download failed for $($app.Name)")
                        continue
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
            
            $postSuccess = $appManager.InvokeStep("Main","Post","Install")
            if (-not $postSuccess) {$this.Logger.Log("WARN", "Main PostInstall step failed")}
        }
        
        "Uninstall" {
            $preSuccess = $appManager.InvokeStep("Main","Pre","Uninstall")
            if (-not $preSuccess) {$this.Logger.Log("WARN", "Main PreUninstall step failed. Proceeding with uninstallation...")}
            [Array]::Reverse($SoftwareList)
            foreach($app in $SoftwareList){
                if (-not (ShouldProcessApp $app)) { continue }
                $logger.Log("PROG", "Processing uninstallation for $($app.Name)")
                if (-not $appManager.Uninstall($app)) {$logger.Log("ERRR", "Uninstallation failed for $($app.Name)");continue}
            }
            $postSuccess = $appManager.InvokeStep("Main","Post","Uninstall")
            if (-not $postSuccess) {$this.Logger.Log("WARN", "Main PostUninstall step failed")}
        }
        
        "Test" {
            $preSuccess = $appManager.InvokeStep("Main","Pre","Test")
            if (-not $preSuccess) {$this.Logger.Log("WARN", "Main PreTest step failed. Proceeding with testing...")}
            foreach ($app in $SoftwareList) {
                if (-not (ShouldProcessApp $app)) { continue }
                $logger.Log("INFO", "Testing $($app.Name)")
                Invoke-Testing -Application $app
            }
            $postSuccess = $appManager.InvokeStep("Main","Post","Test")
            if (-not $postSuccess) {$this.Logger.Log("WARN", "Main PostTest step failed")}
        }
    }
}

# Helper function to determine if an app should be processed
function ShouldProcessApp {param([Parameter()][object]$app);return (-not $TestingMode) -or (-not $app.TestingComplete)}

if ($CleanupCache) {
    $systemOps.CleanupCache(30)
}
if ($PSBoundParameters['Debug']) {$DebugPreference = 'Continue'}
$logger.TrackEvent("ScriptStart", @{Action = $Action;TestingMode = $TestingMode})
try {
    $logger.Log("PROG","Beginning main script execution...")
    $SoftwareList = $configManager.GetSoftwareList($ScriptsDirectory, $SoftwareListFileName)
    if (-not $SoftwareList) {
        $logger.Log("ERRR", "No software found for specified environment and server type.")
        return $false
    }
    $SoftwareList = $configManager.GetSoftwareList($ScriptsDirectory, $SoftwareListFileName)
    if (-not $SoftwareList) {$logger.Log("ERRR", "No software found for specified environment and server type."); return $false}
    if ($ApplicationName) {$SoftwareList = $SoftwareList | Where-Object {$_.Name -eq $ApplicationName -and (-not $ApplicationVersion -or $_.Version -eq $ApplicationVersion)}}
    foreach ($installType in @('Winget', 'PSModule', 'Other', 'Manual')) {
        $currentType = $installType
        $logger.Log("INFO", "Processing $currentType applications")
        $typeList = $SoftwareList | Where-Object { $_.InstallationType -eq $currentType  -and (ShouldProcessApp $_)}
        if ($typeList) {
            $logger.Log("INFO", "Found $($typeList.Count) $currentType applications to process")
            Invoke-MainAction -SoftwareList $typeList
        } else {$logger.Log("INFO", "No $currentType applications found")}
    }
} catch {$logger.TrackEvent("ScriptError", @{Error = $_.Exception.Message;Stack = $_.ScriptStackTrace});throw}
finally {
    $configManager.CleanupOldState(30)
    $systemOps.CleanupCache(30)
    if (Test-Path $StagingDirectory) {Remove-Item -Path $StagingDirectory -Recurse -Force -ErrorAction SilentlyContinue}
    $logger.TrackEvent("ScriptEnd", @{Success = $true;Duration = $ScriptTimeSpan.TotalSeconds;})
}
#endregion