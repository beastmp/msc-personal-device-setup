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
#endregion

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
    if (Test-Path $module.Path) {Import-Module $module.Path -Force -Verbose}
    else {throw "Module file not found: $($module.Path)"}
}

# Initialize managers
try {
    $logger = New-LogManager
    $logger.Log("INFO", "Basic logger created")
    
    $configManager = New-ConfigManager -ConfigPath $ConfigPath -Logger $logger
    $logger.Log("INFO", "ConfigManager initialized successfully")
    
    $logger.Initialize(
        (Join-Path $configManager.ResolvePath('logs') "application.log"),
        (Join-Path $configManager.ResolvePath('logs') "telemetry.log")
    )
    $logger.Log("INFO", "Logger fully initialized with proper paths")
    
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
catch {if($logger){$logger.Log("ERRR", "Failed to initialize managers: $_")}else{Write-Error "Failed to initialize managers: $_"};throw}

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

function Invoke-MainPreStep {[CmdletBinding()]param()
    $logger.Log("INFO", "Starting main pre-step...")
    if (-not (Install-Winget)) {$logger.Log("ERRR", "Failed to install WinGet"); return $false}
    $SoftwareList = $configManager.GetSoftwareList($ScriptsDirectory, $SoftwareListFileName)
    if (-not $SoftwareList) {$logger.Log("ERRR", "No software found for specified environment and server type."); return $false}
    $logger.Log("INFO", "Main pre-step complete")
    return $SoftwareList
}

#region HELPERS
#region     APPLICATION HELPERS
function Install-Winget {[CmdletBinding()]param()
    if(-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        $logger.Log("INFO","Installing WinGet PowerShell module from PSGallery...")
        Install-PackageProvider -Name NuGet -Force | Out-Null
        Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery | Out-Null
        $logger.Log("INFO","Using Repair-WinGetPackageManager cmdlet to bootstrap WinGet...")
        Repair-WinGetPackageManager
        Write-Progress -Completed -Activity "make progress bar dissapear"
        $logger.Log("INFO","Done.")
    }
    return $true
}   
#endregion
#region     STEP HELPERS
function Invoke-MainInstallPreStep {[CmdletBinding()]param()
    $logger.Log("INFO","Starting main install pre-step...")
    foreach ($dir in @($BinariesDirectory, $StagingDirectory, $PostInstallDirectory)) {
        if (-not (Add-Folders -DirPath $dir)) {$logger.Log("ERRR","Failed to add directory $dir");return $false}
    }
    $logger.Log("INFO","Main install pre-step complete")
    return $true
}

function Invoke-MainUninstallPreStep {[CmdletBinding()]param()
    $logger.Log("INFO","Starting main uninstall pre-step...")
    $logger.Log("INFO","Main uninstall pre-step complete")
    return $true
}

function Invoke-MainTestPreStep {[CmdletBinding()]param()
    $logger.Log("INFO","Starting main install pre-step...")
    foreach ($dir in @($BinariesDirectory, $StagingDirectory, $PostInstallDirectory)) {
        if (-not (Add-Folders -DirPath $dir)) {$logger.Log("ERRR","Failed to add directory $dir");return $false}
    }
    $logger.Log("INFO","Main install pre-step complete")
    return $true
}

function Invoke-MainPostStep {[CmdletBinding()]param()
    $logger.Log("INFO","Starting main post-step...")
    $logger.Log("INFO","Main post-step complete")
    # return $true
}

function Invoke-MainInstallPostStep {[CmdletBinding()]param()
    $logger.Log("INFO","Starting main install post-step...")
    $logger.Log("INFO","Main install post-step complete")
    # return $true
}

function Invoke-MainUninstallPostStep {[CmdletBinding()]param()
    $logger.Log("INFO","Starting main uninstall post-step...")
    $logger.Log("INFO","Main uninstall post-step complete")
    return $true
}

function Invoke-MainTestPostStep {[CmdletBinding()]param()
    $logger.Log("INFO","Starting main uninstall post-step...")
    $logger.Log("INFO","Main uninstall post-step complete")
    return $true
}

function Invoke-WithRetry {[CmdletBinding()]param([Parameter(Mandatory)][scriptblock]$ScriptBlock,[string]$Activity,[int]$MaxAttempts = $MaxRetries,[int]$DelaySeconds = $RetryDelay)
    $attempt = 1
    $success = $false
    while(-not $success -and $attempt -le $MaxAttempts){
        try {
            if($attempt -gt 1){$logger.Log("WARN","Retrying $Activity (Attempt $attempt of $MaxAttempts)...")}
            $result = & $ScriptBlock
            $success = $true
            return $result
        } catch {
            if($attempt -eq $MaxAttempts){$logger.Log("ERRR","Failed to $Activity after $MaxAttempts attempts: $_");throw}
            $logger.Log("WARN","Attempt $attempt failed: $_")
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
            $logger.Log("ERRR","Skipping $($app.Name) due to missing dependencies")
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
                $logger.Log("ERRR","Download timeout for $($job.App.Name)")
                $job.PowerShell.Stop()
                $job.Handle.IsCompleted = $true
            }
        }
        Start-Sleep -Seconds 1
    }
    
    foreach ($job in $jobs) {
        try {$job.PowerShell.EndInvoke($job.Handle)}
        catch {$logger.Log("ERRR","Error in parallel download of $($job.App.Name): $_")}
        finally {$job.PowerShell.Dispose()}
    }
    
    $runspacePool.Close()
    $runspacePool.Dispose()
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
function Invoke-DownloadSoftware {[CmdletBinding()]param([Parameter()][object]$Application)
    if(-not $Application.Download) { return $true }
    # Implement file caching
    $cacheKey = "$($Application.Name)_$($Application.Version)"
    $cachePath = Join-Path $BinariesDirectory "$cacheKey.cache"
    
    if (Test-Path $cachePath) {
        $cached = Get-Content $cachePath | ConvertFrom-Json
        if ($cached.Hash -and (Test-FileHash -FilePath $Application.BinaryPath -ExpectedHash $cached.Hash)) {
            $logger.Log("INFO","Using cached version of $($Application.Name) v$($Application.Version)")
            return $true
        }
    }
    
    Invoke-WithRetry -Activity "download $($Application.Name)" -ScriptBlock {
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
    
    # Cache the download info
    $hash=(Get-FileHash -Path $Application.BinaryPath).Hash
    @{Hash=$hash;DateTime=Get-Date -Format "o"} | ConvertTo-Json | Set-Content $cachePath
    
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
                            $downloadJobs += Start-Job -ScriptBlock {param($app);$appManager.Download($app)} -ArgumentList $app
                        }
                        catch {$logger.Log("ERRR", "Failed to initialize $($app.Name): $_");continue}
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
                    if(-not $ParallelDownloads){if(-not $appManager.Download($app)){$logger.Log("ERRR", "Download failed for $($app.Name)");continue}}
                    if(-not $appManager.Install($app)){$logger.Log("ERRR", "Installation failed for $($app.Name)");continue}
                    $timer.Stop()
                    $logger.Log("PROG", "Installation of $($app.Name) completed in $($timer.Elapsed)")
                }
                catch {$logger.Log("ERRR", "Failed to process $($app.Name): $_");continue}
            }
            
            Invoke-MainInstallPostStep
        }
        
        "Uninstall" {
            if(-not(Invoke-MainUninstallPreStep)){return $false}
            [Array]::Reverse($SoftwareList)
            foreach($app in $SoftwareList){
                if (-not (ShouldProcessApp $app)) { continue }
                $logger.Log("PROG", "Processing uninstallation for $($app.Name)")
                if (-not $appManager.Uninstall($app)) {$logger.Log("ERRR", "Uninstallation failed for $($app.Name)");continue}
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
    return (-not $TestingMode) -or (-not $app.TestingComplete)
}

if ($CleanupCache) {
    Remove-OldCache
}

if (-Not (Test-Path -Path $LogDirectory)) {New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null}
$HostName   = hostname
$Version    = $PSVersionTable.PSVersion.ToString()
$logger.SetLogFileFormat($Config.logging.fileNameFormat) # Set the format from config
$FileName = $logger.GetLogFileName("Transcript", $Action, $HostName, $Version)
$FilePath   = Join-Path -Path $LogDirectory -ChildPath $FileName
Start-Transcript -IncludeInvocationHeader -NoClobber -Path $FilePath
if ($PSBoundParameters['Debug']) {$DebugPreference = 'Continue'}
$ScriptStart = Get-Date
# Set-Location -Path $ScriptsDirectory

try {
    $logger.Log("PROG","Beginning main script execution...")
    $logger.TrackEvent("ScriptStart", @{
        Action = $Action
        TestingMode = $TestingMode
    })
    
    $SoftwareList = Invoke-MainPreStep

    if ($ApplicationName) {
        $SoftwareList = $SoftwareList | Where-Object { 
            $_.Name -eq $ApplicationName -and 
            (-not $ApplicationVersion -or $_.Version -eq $ApplicationVersion)
        }
    }

    # Process software by installation type - Fix the loop structure
    foreach ($installType in @('Winget', 'PSModule', 'Other', 'Manual')) {
        $currentType = $installType
        $logger.Log("INFO", "Processing $currentType applications")
        
        $typeList = $SoftwareList | Where-Object { $_.InstallationType -eq $currentType  -and (ShouldProcessApp $_)}
        
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
$logger.Log("PROG",$("Main script execution completed in {0:00}:{1:00}:{2:00}:{3:00}" -f $ScriptTimeSpan.days,$ScriptTimeSpan.hours,$ScriptTimeSpan.minutes,$ScriptTimeSpan.seconds))
Stop-Transcript | Out-Null
#endregion