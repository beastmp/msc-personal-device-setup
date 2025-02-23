<#
.SYNOPSIS
    Main installation script for personal device setup.
.DESCRIPTION
    Manages installation, uninstallation, and testing of applications using various package managers.
#>

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
