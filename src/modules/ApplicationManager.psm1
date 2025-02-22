using namespace System.Collections
using namespace System.IO
using namespace System.Version

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
    
    # Path properties
    [string]$BinaryPath
    [string]$StagedPath 
    [string]$InstallPath
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

class ApplicationManager {
    hidden [object]$SystemOps
    hidden [object]$StateManager
    hidden [object]$Logger
    hidden [object]$ConfigManager
    
    ApplicationManager([object]$sysOps,[object]$stateManager,[object]$logger,[object]$configManager) {
        $this.SystemOps = $sysOps
        $this.StateManager = $stateManager
        $this.Logger = $logger
        $this.ConfigManager = $configManager
    }

    [ApplicationConfig]InitializeApplication([ApplicationConfig]$app) {
        $this.Logger.Log("INFO", "Initializing application paths for $($app.Name)")
        try {
            $InstallDirectory = $this.ConfigManager.ResolvePath('install')
            $BinariesDirectory = $this.ConfigManager.ResolvePath('binaries')
            $StagingDirectory = $this.ConfigManager.ResolvePath('staging')
            $PostInstallDirectory = $this.ConfigManager.ResolvePath('postInstall')

            $ext = if($app.InstallationType -eq "Winget"){".exe"}
            else {
                if($app.DownloadURL) {
                    $urlExt = [System.IO.Path]::GetExtension($app.DownloadURL)
                    if ([string]::IsNullOrEmpty($urlExt) -or $urlExt.Length -gt 5) {
                        $this.Logger.Log("VRBS", "Invalid or missing extension from URL, defaulting to .exe")
                        ".exe"
                    } else {$urlExt}
                } else {$this.Logger.Log("VRBS", "No download URL specified, defaulting to .exe");".exe"}
            }

            $appBaseName = "$($app.Name)_$($app.Version)"
            if (-not $app.InstallPath) {
                $pathParts = $app.Name.Split('_')
                $app.InstallPath = Join-Path $InstallDirectory ($pathParts -join '\')
                $this.Logger.Log("VRBS", "Set install path to: $($app.InstallPath)")
            }
            $app.BinaryPath = Join-Path $BinariesDirectory "$appBaseName$ext"
            $this.Logger.Log("VRBS", "Set binary path to: $($app.BinaryPath)")
            $app.StagedPath = Join-Path $StagingDirectory "$appBaseName$ext"
            $this.Logger.Log("VRBS", "Set staged path to: $($app.StagedPath)")
            $app.PostInstallPath = Join-Path $PostInstallDirectory "$appBaseName$ext"
            $this.Logger.Log("VRBS", "Set post-install path to: $($app.PostInstallPath)")

            $app = $this.ProcessInstallationArguments($app)
            $this.Logger.Log("INFO", "Application paths initialized successfully")
        }
        catch {$this.Logger.Log("ERRR", "Failed to initialize application paths: $_");throw}
        return $app
    }

    hidden [object]ProcessInstallationArguments([object]$app) {
        $this.Logger.Log("VRBS", "Processing installation arguments for $($app.Name)")
        $variables = @{
            '$Name' = $app.Name
            '$Version' = $app.Version
            '$StagedPath' = $app.StagedPath
            '$InstallPath' = $app.InstallPath
            '$BinariesDirectory' = $this.ConfigManager.ResolvePath('binaries')
            '$StagingDirectory' = $this.ConfigManager.ResolvePath('staging')
        }

        if ($app.InstallerArguments) {
            $this.Logger.Log("VRBS", "Processing installer arguments")
            $processedArgs = $app.InstallerArguments | ForEach-Object {
                $arg = $_
                foreach ($var in $variables.GetEnumerator()) {
                    if ($arg -match [regex]::Escape($var.Key)) {
                        $this.Logger.Log("DBUG", "Replacing $($var.Key) with $($var.Value) in argument")
                        $arg = $arg.Replace($var.Key, $var.Value)
                    }
                }
                $arg
            }
            $app.InstallerArguments = $processedArgs
            $this.Logger.Log("DBUG", "Final installer arguments: $($app.InstallerArguments)")
        }

        # Process uninstaller arguments
        if ($app.UninstallerArguments) {
            $this.Logger.Log("VRBS", "Processing uninstaller arguments")
            $processedArgs = $app.UninstallerArguments -split ';' | ForEach-Object {
                $arg = $_
                foreach ($var in $variables.GetEnumerator()) {
                    if ($arg -match [regex]::Escape($var.Key)) {
                        $this.Logger.Log("DBUG", "Replacing $($var.Key) with $($var.Value) in argument")
                        $arg = $arg.Replace($var.Key, $var.Value)
                    }
                }
                $arg
            }
            $app.UninstallerArguments = $processedArgs -join ';'
            $this.Logger.Log("DBUG", "Final uninstaller arguments: $($app.UninstallerArguments)")
        }
        return $app
    }

    [bool]Download([ApplicationConfig]$app) {
        if(-not $app.Download){return $true}
        return $this.SystemOps.InvokeWithRetry({
            $preSuccess = $this.InvokeStep($app.Name,"Pre","Download",$app)
            if (-not $preSuccess) {$this.Logger.Log("WARN", "$($app.Name) PreDownload step failed. Proceeding with download...")}
            $cacheKey = "$($app.Name)_$($app.Version)"
            $cachePath = Join-Path $this.ConfigManager.ResolvePath('binaries') "$cacheKey.cache"
            if (Test-Path $cachePath) {
                $cached = Get-Content $cachePath | ConvertFrom-Json
                if ($cached.Hash -and ($this.SystemOps.ValidateFileHash($app.BinaryPath, $cached.Hash))) {
                    $this.Logger.Log("INFO", "Using cached version of $($app.Name)")
                    return $true
                }
            }
            $success = switch ($app.InstallationType) {
                "Winget"    {$this.DownloadWingetPackage($app)}
                "PSModule"  {return $true}
                default     {$this.DownloadDirectPackage($app)}
            }
            if ($success) {
                $hash = (Get-FileHash -Path $app.BinaryPath).Hash
                @{Hash=$hash;DateTime=Get-Date -Format "o"} | ConvertTo-Json | Set-Content $cachePath
                $postSuccess = $this.InvokeStep($app.Name,"Post","Download",$app)
                if (-not $postSuccess) {$this.Logger.Log("WARN", "$($app.Name) PostDownload step failed")}
            }
            return $success
        }, "download $($app.Name)")
    }
    
    [bool]DownloadAll([array]$applications, [bool]$requestParallel = $false) {
        $useParallel = $requestParallel -and $this.SystemOps.ParallelEnabled
        if ($useParallel) {
            $scriptBlock = {param($app);$this.Download($app)}
            $results = $this.SystemOps.InvokeParallel($scriptBlock, $applications)
            return -not ($results -contains $false)
        }else{foreach ($app in $applications) {if (-not $this.Download($app)) {return $false}};return $true}
    }

    [bool]Install([ApplicationConfig]$app) {
        if(-not $app.Install){return $true}
        return $this.SystemOps.InvokeWithRetry({
            $preSuccess = $this.InvokeStep($app.Name,"Pre","Install",$app)
            if (-not $preSuccess) {$this.Logger.Log("WARN", "$($app.Name) PreInstall step failed. Proceeding with installation...")}
            if($app.SymLinkPath){$this.SystemOps.AddSymLink($app.SymLinkPath,$app.InstallPath)}
            $success = switch ($app.InstallationType) {
                "Winget"    {$this.InstallWingetPackage($app)}
                "PSModule"  {$this.InstallPSModule($app)}
                default     {$this.InstallDirectPackage($app)}
            }
            if($success) {
                if($app.ProcessIDs) {foreach($procId in $app.ProcessIDs) {$this.SystemOps.KillProcess($procId)}}
                $postSuccess = $this.InvokeStep($app.Name,"Post","Install",$app)
                if (-not $postSuccess) {$this.Logger.Log("WARN", "$($app.Name) PostInstall step failed")}
                if(Test-Path $app.StagedPath) {$this.SystemOps.MoveFolder($app.StagedPath, $app.PostInstallPath)}
            }
            return $success
        }, "install $($app.Name)")
    }
    
    [bool]Uninstall([ApplicationConfig]$app) {
        return $this.SystemOps.InvokeWithRetry({
            $preSuccess = $this.InvokeStep($app.Name,"Pre","Uninstall",$app)
            if (-not $preSuccess) {$this.Logger.Log("WARN", "$($app.Name) PreUninstall step failed. Proceeding with uninstallation...")}
            $success = switch($app.InstallationType) {
                "Winget"    {$this.UninstallWingetPackage($app)}
                "PSModule"  {$this.UninstallPSModule($app)}
                default     {$this.UninstallDirectPackage($app)}
            }
            if($success) {
                $postSuccess = $this.InvokeStep($app.Name,"Post","Uninstall",$app)
                if (-not $postSuccess) {$this.Logger.Log("WARN", "$($app.Name) PostUninstall step failed")}
                    if($app.InstallPath -and (Test-Path $app.InstallPath)) {
                    Remove-Item -Path $app.InstallPath -Recurse -Force
                }
            }
            return $success
        }, "uninstall $($app.Name)")
    }

    hidden [bool]InvokeStep([string]$appName,[string]$prefix,[string]$action) {return $this.InvokeStep($appName,$prefix,$action,$null)}
    
    hidden [bool]InvokeStep([string]$appName,[string]$prefix,[string]$action,[ApplicationConfig]$app=$null) {
        $functionName = "Invoke-${appName}_${prefix}${action}"
        $success = $true
        if(Get-Command $functionName -ErrorAction SilentlyContinue) {
            $this.Logger.Log("INFO", "Starting $("${appName} ${prefix}${action}") step...")
            $success = if($app){& $functionName -Application $app}else{& $functionName}
        } else {$this.Logger.Log("VRBS", "$("${appName} ${prefix}${action}") step not defined - SKIPPING")}
        if ($success) {$this.Logger.Log("SCSS", "$("${appName} ${prefix}${action}") step completed successfully")}
        else {$this.Logger.Log("ERRR", "$("${appName} ${prefix}${action}") step failed")}
        return $success
    }
    
    hidden [bool]DownloadWingetPackage([ApplicationConfig]$app) {
        $TempBinaryPath = $($app.BinaryPath).Replace([System.IO.Path]::GetExtension($app.BinaryPath), "")
        $this.Logger.Log("INFO", "Downloading $($app.Name) from winget to $TempBinaryPath")
        $this.SystemOps.AddFolders($TempBinaryPath)
        $version=(Find-WinGetPackage -Id $app.ApplicationID -MatchOption Equals).Version
        $DownloadArguments=@("--version", $version,"--download-directory", "`"$TempBinaryPath`"","--accept-source-agreements","--accept-package-agreements")
        if ($app.MachineScope){$DownloadArguments += @("--scope", "machine")}
        try {
            $Process = $this.SystemOps.StartProcess("winget", @("download", "--id", $app.ApplicationID) + $DownloadArguments)
            if ($Process.ExitCode -eq 0) {$this.Logger.Log("SCSS", "$($app.Name) v$version downloaded successfully")}
            else {$this.Logger.Log("ERRR", "Download failed with exit code $($Process.ExitCode)");return $false}
            Get-ChildItem -Path $TempBinaryPath | ForEach-Object {
                $NewFileName = if($_.PSIsContainer) {"$($app.Name)_$($app.Version)_$($_.Name)"} else {"$($app.Name)_$($app.Version)$($_.Extension)"}
                $destinationPath = Join-Path -Path $this.ConfigManager.ResolvePath('binaries') -ChildPath $NewFileName
                $this.SystemOps.MoveFolder($_.FullName, $destinationPath)
            }
            Remove-Item -Path $TempBinaryPath -Recurse -Force
            return $true
        } catch {$this.Logger.Log("ERRR", "Failed to download: $_");return $false}
    }
    
    hidden [bool]DownloadDirectPackage([ApplicationConfig]$app) {
        if (-not (Test-Path $app.BinaryPath)) {
            $this.Logger.Log("INFO", "Downloading $($app.Name) from $($app.DownloadURL)")
            try {Invoke-WebRequest -Uri $app.DownloadURL -OutFile $app.BinaryPath;$this.Logger.Log("SCSS", "Download completed")}
            catch {$this.Logger.Log("ERRR", "Download failed: $_");return $false}
        }
        try {Copy-Item -Path $app.BinaryPath -Destination $app.StagedPath -Force;return $true}
        catch {$this.Logger.Log("ERRR", "Failed to copy to staging: $_");return $false}
    }
    
    hidden [bool]InstallWingetPackage([ApplicationConfig]$app) {
        $version = (Find-WinGetPackage -Id $app.ApplicationID -MatchOption Equals).Version
        $this.Logger.Log("INFO", "Installing $($app.Name) v$version")
        $InstallArguments = @("--accept-source-agreements","--accept-package-agreements","--force")
        if ($app.InstallerArguments) {$InstallArguments += $app.InstallerArguments}
        $this.Logger.log("DBUG", "Installer arguments: $($InstallArguments -join ', ')")
        $this.Logger.log("DBUG", "Application Download: $($app.Download)")
        $this.Logger.log("DBUG", "Application BinaryPath: $($app.BinaryPath)")
        $ApplicationArguments = if($app.Download -and (Test-Path -Path $($app.BinaryPath).Replace([System.IO.Path]::GetExtension($app.BinaryPath), ".yaml"))) {
            @("--manifest", $($app.BinaryPath).Replace([System.IO.Path]::GetExtension($app.BinaryPath), ".yaml"))
        } else {@("--id", $app.ApplicationID)}
        $this.Logger.Log("DBUG", "Application arguments: $($ApplicationArguments -join ', ')")
        try {$Process = $this.SystemOps.StartProcess("winget", @("install") + $ApplicationArguments + $InstallArguments);return $Process.ExitCode -eq 0}
        catch {$this.Logger.Log("ERRR", "Installation failed: $_");return $false}
    }
    
    hidden [bool]InstallPSModule([ApplicationConfig]$app) {
        $installParams = @{Name=$app.ModuleID;Force=$true;Confirm=$false}
        if ($app.Version -ne "latest") {$installParams.RequiredVersion = $app.Version}
        try {Install-Module @installParams;return $true}
        catch {$this.Logger.Log("ERRR", "Failed to install PS module: $_");return $false}
        return $true # Default return for unexpected paths
    }
    
    hidden [bool]InstallDirectPackage([ApplicationConfig]$app) {
        if(-not $app.StagedPath){$this.Logger.Log("ERRR","No staged path specified");return $false}
        $FileType = [System.IO.Path]::GetExtension($app.StagedPath)
        return switch ($FileType) {
            ".zip"
            {
                try {Expand-Archive -Path $app.StagedPath -DestinationPath $app.InstallPath -Force;$true}
                catch {$this.Logger.Log("ERRR", "Failed to extract ZIP: $_");$false}
            }
            ".msi"
            {
                $Arguments = @("/i", "`"$($app.StagedPath)`"", "/passive", "/norestart") + $app.InstallerArguments
                $Process = $this.SystemOps.StartProcess("msiexec.exe", $Arguments)
                $Process.ExitCode -eq 0
            }
            ".exe"
            {$Process = $this.SystemOps.StartProcess($app.StagedPath, $app.InstallerArguments);$Process.ExitCode -eq 0}
            default
            {$this.Logger.Log("ERRR", "Unsupported file type: $FileType");$false}
        }
    }

    hidden [bool]UninstallWingetPackage([ApplicationConfig]$app) {
        $UninstallArguments = @("--silent","--force","--disable-interactivity","--ignore-warnings")
        try {$Process = $this.SystemOps.StartProcess("winget", @("uninstall", "--id", $app.ApplicationID) + $UninstallArguments);return $Process.ExitCode -eq 0}
        catch {$this.Logger.Log("ERRR", "Uninstallation failed: $_");return $false}
    }
    
    hidden [bool]UninstallPSModule([ApplicationConfig]$app) {
        try {Uninstall-Module -Name $app.ModuleID -Force -AllVersions;return $true}
        catch {$this.Logger.Log("ERRR", "Failed to uninstall PS module: $_");return $false}
    }
    
    hidden [bool]UninstallDirectPackage([ApplicationConfig]$app) {
        if (-not $app.PostInstallPath) {$this.Logger.Log("ERRR", "No post-install path specified");return $false}

        $FileType = [System.IO.Path]::GetExtension($app.PostInstallPath)
        return $(switch ($FileType) {
            ".msi"
            {$Process = $this.SystemOps.StartProcess("msiexec.exe", @("/x", $app.PostInstallPath, "/qb!"));$Process.ExitCode -eq 0}
            ".exe"
            {
                if ($app.UninstallerArguments) {$Process = $this.SystemOps.StartProcess($app.PostInstallPath, $app.UninstallerArguments);return $Process.ExitCode -eq 0}
                else {Remove-Item -Path $app.InstallPath -Recurse -Force -ERRRAction SilentlyContinue; return $true}
            }
            default
            {if (Test-Path $app.InstallPath) {Remove-Item -Path $app.InstallPath -Recurse -Force -ERRRAction SilentlyContinue; return $true}}
        })
    }
}

function New-ApplicationManager {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][object]$SystemOps,
        [Parameter(Mandatory=$true)][object]$StateManager,
        [Parameter(Mandatory=$true)][object]$Logger,
        [Parameter(Mandatory=$true)][object]$ConfigManager
    )
    
    return [ApplicationManager]::new($SystemOps, $StateManager, $Logger, $ConfigManager)
}

Export-ModuleMember -Function New-ApplicationManager
