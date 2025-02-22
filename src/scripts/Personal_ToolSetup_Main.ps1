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
Write-Verbose "[$(Get-Date -f 'yyyyMMdd_HHmmss')] [VRBS] Module path resolved to: $modulePath"
$moduleOrder = @(
    @{Name="ConfigManager"; Path=Join-Path $modulePath "ConfigManager.psm1"},
    @{Name="SystemOperations"; Path=Join-Path $modulePath "SystemOperations.psm1"},
    @{Name="Monitoring"; Path=Join-Path $modulePath "Monitoring.psm1"},
    @{Name="StateManager"; Path=Join-Path $modulePath "StateManager.psm1"},
    @{Name="ApplicationManager"; Path=Join-Path $modulePath "ApplicationManager.psm1"}
)
foreach ($module in $moduleOrder) {
    Write-Verbose "[$(Get-Date -f 'yyyyMMdd_HHmmss')] [VRBS] Loading module: $($module.Name) from $($module.Path)"
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
    
    $stateManager = New-StateManager -StateFile $configManager.GetStatePath() -Logger $logger
    $logger.Log("VRBS", "StateManager initialized successfully")
    
    $systemOps = New-SystemOperations -BinDir $configManager.ResolvePath("binaries") `
                                    -StagingDir $configManager.ResolvePath("staging") `
                                    -InstallDir $configManager.ResolvePath("install") `
                                    -Logger $logger `
                                    -Config $configManager.Config
    $logger.Log("VRBS", "SystemOperations initialized successfully")
    
    $appManager = New-ApplicationManager -SystemOps $systemOps `
                                       -StateManager $stateManager `
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

#region HELPERS
#region     APPLICATION HELPERS
#endregion
#region     STEP HELPERS
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
                $logger.Log("ERRR","Dependency $($dep.Name) not found at $($dep.InstallPath)")
                return $false
            }
        }
        elseif ($dep.Type -eq "WindowsFeature") {
            $feature = Get-WindowsOptionalFeature -Online -FeatureName $dep.Name
            if ($feature.State -ne "Enabled") {
                $logger.Log("ERRR","Required Windows feature $($dep.Name) is not enabled")
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
        $CustomAttributeSeparators = @("=",":"," ")
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
#region DOWNLOAD
function Invoke-DownloadSoftware {
    [CmdletBinding()]
    param([Parameter()][object]$Application)
    
    if(-not $Application.Download) { return $true }
    
    $cacheKey = "$($Application.Name)_$($Application.Version)"
    $cachePath = Join-Path $BinariesDirectory "$cacheKey.cache"
    
    if (Test-Path $cachePath) {
        $cached = Get-Content $cachePath | ConvertFrom-Json
        if ($cached.Hash -and (Test-FileHash -FilePath $Application.BinaryPath -ExpectedHash $cached.Hash)) {
            $logger.Log("INFO", "Using cached version of $($Application.Name) v$($Application.Version)")
            return $true
        }
    }
    
    $downloadScript = {
        if ($Application.InstallationType -eq "Winget") {
            $TempBinaryPath = $($Application.BinaryPath).Replace([System.IO.Path]::GetExtension($Application.BinaryPath), "")
            $logger.Log("INFO","Downloading $($Application.Name) version $($Application.Version) from winget to $TempBinaryPath...")
            Add-Folders -DirPath $TempBinaryPath
            $version = (Find-WinGetPackage -Id $Application.ApplicationID -MatchOption Equals).Version
            $DownloadArguments = @("--version",$version,"--download-directory", "`"$TempBinaryPath`"","--accept-source-agreements","--accept-package-agreements")
            if ($Application.MachineScope) {$DownloadArguments += @("--scope","machine")}
            try {
                $Process = Invoke-Process -Path "winget" -Action "download" -Application @("--id",$Application.ApplicationID) -Arguments $DownloadArguments
                if ($Process.ExitCode -eq 0 -or $null -eq $Process.ExitCode) {
                    $logger.Log("SCSS","$($Application.Name) v$version downloaded successfully")
                } else {
                    $errorMessage = $process.StandardError.ReadToEnd()
                    $logger.Log("ERRR","$($Application.Name) download failed with exit code $($process.ExitCode). Error: $errorMessage")
                    return $false
                }
            }
            catch{$logger.Log("ERRR","Unable to download $($Application.Name) using winget"); $logger.Log("DBUG","Error: $($_.Exception.Message)"); return $false}
            $files = Get-ChildItem -Path $TempBinaryPath
            foreach ($file in $files) {
                $NewFileName = if($file.PSIsContainer) {"$($Application.Name)_$($Application.Version)_$($file.Name)"}
                else{"$($Application.Name)_$($Application.Version)$($file.Extension)"}
                $destinationPath = Join-Path -Path $BinariesDirectory -ChildPath $NewFileName
                $logger.Log("VRBS","Moving file $($file.FullName) to $destinationPath")
                try {
                    Move-Item -Path $file.FullName -Destination $destinationPath -Force
                    $logger.Log("VRBS","Moved $($file.Name) to $destinationPath")
                } catch {$logger.Log("ERRR","Failed to move $($file.Name) to $destinationPath. Error: $($_.Exception.Message)")}
            }
            # Remove the application binary path after moving files
            try {
                Remove-Item -Path $TempBinaryPath -Recurse -Force
                $logger.Log("VRBS","Removed application binary path: $TempBinaryPath")
            } catch {$logger.Log("ERRR","Failed to remove application binary path: $TempBinaryPath. Error: $($_.Exception.Message)")}
        } else {
            $logger.Log("VRBS","Checking for $($Application.Name) version $($Application.Version) in $($Application.BinaryPath)...")
            if (-not (Test-Path $($Application.BinaryPath))) {
                $logger.Log("INFO","Downloading $($Application.Name) version $($Application.Version) from $($Application.DownloadURL) to $($Application.BinaryPath)...")
                $logger.Log("VRBS","Executing Invoke-WebRequest for $($Application.DownloadURL) to $($Application.BinaryPath)")
                try {
                    Invoke-WebRequest -Uri $Application.DownloadURL -OutFile $($Application.BinaryPath)
                    $logger.Log("SCSS","Download of $($Application.Name) v$($Application.Version) completed successfully")
                }
                catch {$logger.Log("ERRR","Execution of Invoke-WebRequest for $($Application.DownloadURL) to $($Application.BinaryPath) unsuccessful");return $false}
            } else {$logger.Log("WARN","$($Application.Name) v$($Application.Version) already exists in $($Application.BinaryPath)")}
        }
        $logger.Log("VRBS","Copying from $($Application.BinaryPath) to $($Application.StagedPath)")
        if(Test-Path $($Application.BinaryPath)) {
            try {Copy-Item -Path $($Application.BinaryPath) -Destination $($Application.StagedPath) -Force}
            catch {$logger.Log("ERRR","Unable to copy from $($Application.BinaryPath) to $($Application.StagedPath)");return $false}
        }
        Invoke-ScriptStep -StepName "PostDownload" -Application $Application
    }
    
    $systemOps.InvokeWithRetry($downloadScript, "download $($Application.Name)")
    
    # Cache the download info
    $hash = (Get-FileHash -Path $Application.BinaryPath).Hash
    @{Hash=$hash; DateTime=Get-Date -Format "o"} | ConvertTo-Json | Set-Content $cachePath
    
    return $true
}
#endregion
#region INSTALL
function Invoke-InstallSoftware {[CmdletBinding()]param([Parameter()][object]$Application)
    if($Application.Install) {
        if (-not (Invoke-ScriptStep -StepName "PreInstall" -Application $Application)) {$logger.Log("ERRR","Pre-install step failed"); return $false}
        if($Application.SymLinkPath){Add-SymLink -SourcePath $Application.SymLinkPath -TargetPath $Application.InstallPath}
        # $logger.Log("INFO","Starting installation of $($Application.Name) v$($Application.Version)...")
        if ($Application.InstallationType -eq "Winget") {
            $version = (Find-WinGetPackage -Id $Application.ApplicationID -MatchOption Equals).Version
            $logger.Log("INFO","Installing $($Application.Name) v$version from winget...")
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
                    $logger.Log("SCSS","$($Application.Name) v$version installed successfully")
                } else {
                    $logger.Log("ERRR","$($Application.Name) installation failed with exit code $($Process.ExitCode)")
                    return $false
                }
            }
            catch{$logger.Log("ERRR","Unable to install $($Application.Name) using winget"); $logger.Log("DBUG","Error: $($_.Exception.Message)"); return $false}
        } elseif ($Application.InstallationType -eq "PSModule") {
            Install-PSModule -ModuleName $Application.ModuleID
        } else {
            $FileType = [System.IO.Path]::GetExtension($Application.StagedPath)
            switch ($FileType) {
                ".zip" {
                    $logger.Log("INFO","Extracting ZIP file for $($Application.Name) v$($Application.Version) to $($Application.InstallPath)...")
                    $logger.Log("DBUG","Executing Expand-Archive -Path $($Application.StagedPath) -DestinationPath $($Application.InstallPath) -Force")
                    try{
                        Expand-Archive -Path $Application.StagedPath -DestinationPath $Application.InstallPath -Force
                        $logger.Log("SCSS","$($Application.Name) v$version extracted successfully")
                    }
                    catch{$logger.Log("ERRR","Extraction of $($Application.StagedPath) to $($Application.InstallPath) failed"); return $false}
                }
                ".msi" {
                    $logger.Log("INFO","Running MSI installer for $($Application.Name) v$($Application.Version)...")
                    try{
                        $BaseArguments = @("/passive","/norestart")
                        $InstallArguments = $Application.InstallArguments + $BaseArguments
                        Invoke-Process -Path "msiexec.exe" -Action "/i" -Application @("`"$($Application.StagedPath)`"") -Arguments $InstallArguments -Wait
                        $logger.Log("SCSS","$($Application.Name) v$version installed successfully")
                    }
                    catch{$logger.Log("ERRR","Installation of $($Application.Name) v$($Application.Version) failed"); return $false}
                }
                ".exe" {
                    $logger.Log("INFO","Running installer for $($Application.Name) v$($Application.Version)...")
                    try{
                        $Process = Invoke-Process -Path $Application.StagedPath -Arguments $Application.InstallerArguments
                        if ($Process.ExitCode -eq 0 -or $null -eq $Process.ExitCode) {
                                    $logger.Log("SCSS","$($Application.Name) v$version installed successfully")
                        } else {
                            $logger.Log("ERRR","$($Application.Name) installation failed with exit code $($Process.ExitCode)")
                            return $false
                        }
                        # $logger.Log("SCSS","$($Application.Name) v$version installed successfully")
                    }
                    catch{$logger.Log("ERRR","Installation of $($Application.Name) v$($Application.Version) failed"); return $false}
                }
            }
        }
        if($Application.ProcessIDs){foreach($Process in $Application.ProcessIDs){Invoke-KillProcess $Process}}
        Invoke-ScriptStep -StepName "PostInstall" -Application $Application
        if(-not((Test-Path $Application.InstallPath) -and (Get-ChildItem -Path $Application.InstallPath).Count -gt 0)) {
            $logger.Log("WARN","Validation of InstallPath ($($Application.InstallPath)) failed for $($Application.Name) v$($Application.Version)")
        }
    } else {$logger.Log("VRBS","Install flag for $($Application.Name) v$($Application.Version) set to false")}
    if(Test-Path $($Application.StagedPath)) {
        $logger.Log("VRBS","Executing Move-Item from $($Application.StagedPath) to $($Application.PostInstallPath)")
        try{Move-Item -Path $Application.StagedPath -Destination $Application.PostInstallPath -Force}
        catch{$logger.Log("ERRR","Unable to move item from $($Application.StagedPath) to $($Application.PostInstallPath)"); return $false}
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

if ($CleanupCache) {Remove-OldCache}
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
    $stateManager.CleanupOldStates(30)
    if (Test-Path $StagingDirectory) {Remove-Item -Path $StagingDirectory -Recurse -Force -ErrorAction SilentlyContinue}
    $logger.TrackEvent("ScriptEnd", @{Success = $true;Duration = $ScriptTimeSpan.TotalSeconds;})
}
#endregion