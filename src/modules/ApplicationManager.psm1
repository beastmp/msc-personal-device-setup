using namespace System.Collections
using namespace System.IO
using module .\Types.psm1

class ApplicationManager {
    hidden [object]$SystemOps
    hidden [object]$StateManager
    hidden [object]$Logger
    hidden [object]$ConfigManager
    
    ApplicationManager(
        [object]$sysOps,
        [object]$stateManager,
        [object]$logger,
        [object]$configManager
    ) {
        $this.SystemOps = $sysOps
        $this.StateManager = $stateManager
        $this.Logger = $logger
        $this.ConfigManager = $configManager
    }

    [void]InitializeApplication([object]$Application) {
        $InstallDirectory = $this.ConfigManager.ResolvePath('install')
        $BinariesDirectory = $this.ConfigManager.ResolvePath('binaries')
        $StagingDirectory = $this.ConfigManager.ResolvePath('staging')
        $PostInstallDirectory = $this.ConfigManager.ResolvePath('postInstall')

        $ext = if($Application.InstallationType -eq "Winget"){".exe"}
        else{
            if($Application.DownloadURL) {
                $urlExt = [System.IO.Path]::GetExtension($Application.DownloadURL)
                if ([string]::IsNullOrEmpty($urlExt) -or $urlExt.Length -gt 5){".exe"}else{$urlExt}
            }else{".exe"}
        }
        $appBaseName = "$($Application.Name)_$($Application.Version)"
        if (-not $Application.InstallPath) {
            $pathParts = $Application.Name.Split('_')
            $Application.InstallPath = Join-Path $InstallDirectory ($pathParts -join '\')
        }
        $Application.BinaryPath = Join-Path $BinariesDirectory "$appBaseName$ext"
        $Application.StagedPath = Join-Path $StagingDirectory "$appBaseName$ext"
        $Application.PostInstallPath = Join-Path $PostInstallDirectory "$appBaseName$ext"
        $this.ProcessInstallationArguments($Application)
    }

    hidden [void]ProcessInstallationArguments([object]$Application) {
        $InstallDirectory = $this.ConfigManager.ResolvePath('install')
        $BinariesDirectory = $this.ConfigManager.ResolvePath('binaries')
        $StagingDirectory = $this.ConfigManager.ResolvePath('staging')
        $PostInstallDirectory = $this.ConfigManager.ResolvePath('postInstall')
        $variables = @{'$Name'=$Application.Name;'$Version'=$Application.Version;'$StagedPath'=$Application.StagedPath;'$InstallPath'=$Application.InstallPath;'$BinariesDirectory'=$BinariesDirectory;'$StagingDirectory'=$StagingDirectory}

        # Process installer arguments
        if ($Application.InstallerArguments) {
            $processedArgs = $Application.InstallerArguments | ForEach-Object {
                $arg = $_
                foreach ($var in $variables.GetEnumerator()) {$arg = $arg.Replace("`$$($var.Key)", $var.Value)}
                $arg
            }
            $Application.InstallerArguments = $processedArgs
        }

        # Process uninstaller arguments
        if ($Application.UninstallerArguments) {
            $processedArgs = $Application.UninstallerArguments | ForEach-Object {
                $arg = $_
                foreach ($var in $variables.GetEnumerator()) {$arg = $arg.Replace("`$$($var.Key)", $var.Value)}
                $arg
            }
            $Application.UninstallerArguments = $processedArgs
        }
    }

    [bool]Download([ApplicationConfig]$app) {
        $this.InitializeApplication($app)
        if(-not $app.Download) { return $true }
        $cacheKey = "$($app.Name)_$($app.Version)"
        $cachePath = Join-Path $this.ConfigManager.ResolvePath('binaries') "$cacheKey.cache"
        # Check cache
        if (Test-Path $cachePath) {
            $cached = Get-Content $cachePath | ConvertFrom-Json
            if ($cached.Hash -and ($this.SystemOps.ValidateFileHash($app.BinaryPath, $cached.Hash))) {
                $this.Logger.Log("INFO", "Using cached version of $($app.Name)")
                return $true
            }
        }
        # Handle different installation types
        try {
            $success = switch ($app.InstallationType) {
                "Winget" { $this.DownloadWingetPackage($app) }
                "PSModule" { $true } # No download needed for PS modules
                default { $this.DownloadDirectPackage($app) }
            }
            if ($success) {
                # Cache the download info if successful
                $hash = (Get-FileHash -Path $app.BinaryPath).Hash
                @{Hash=$hash;DateTime=Get-Date -Format "o"} | ConvertTo-Json | Set-Content $cachePath
            }
            return $success
        }
        catch {
            $this.Logger.Log("ERROR", "Unexpected error during download: $_")
            return $false
        }
    }
    
    [bool]Install([ApplicationConfig]$app) {
        if(-not $app.Install) { return $true }
        if (-not $this.InvokePreStep($app, "PreInstall")) { return $false }
        # Create symlinks if specified
        if($app.SymLinkPath) {$this.SystemOps.AddSymLink($app.SymLinkPath, $app.InstallPath)}
        # Handle different installation types
        $success = switch ($app.InstallationType) {
            "Winget" { $this.InstallWingetPackage($app) }
            "PSModule" { $this.InstallPSModule($app) }
            default { $this.InstallDirectPackage($app) }
        }
        if($success) {
            if($app.ProcessIDs) {foreach($procId in $app.ProcessIDs) {$this.SystemOps.KillProcess($procId)}}
            $this.InvokePostStep($app, "PostInstall")
            # Move staged files to post-install location
            if(Test-Path $app.StagedPath) {$this.SystemOps.MoveFolder($app.StagedPath, $app.PostInstallPath)}
        }
        return $success
    }
    
    [bool]Uninstall([ApplicationConfig]$app) {
        if (-not $this.InvokePreStep($app, "PreUninstall")) { return $false }
        $success = switch ($app.InstallationType) {
            "Winget" { $this.UninstallWingetPackage($app) }
            "PSModule" { $this.UninstallPSModule($app) }
            default { $this.UninstallDirectPackage($app) }
        }
        if($success) {
            $this.InvokePostStep($app, "PostUninstall")
            # Cleanup installation directory
            if($app.InstallPath -and (Test-Path $app.InstallPath)) {Remove-Item -Path $app.InstallPath -Recurse -Force}
        }
        return $success
    }
    
    # Private helper methods
    hidden [bool]InvokePreStep([ApplicationConfig]$app, [string]$stepName) {
        $functionName = "Invoke-${stepName}_$($app.Name)"
        if(Get-Command $functionName -ErrorAction SilentlyContinue) {
            $this.Logger.Log("INFO", "Running $stepName for $($app.Name)")
            return & $functionName -Application $app
        }
        return $true
    }
    
    hidden [bool]InvokePostStep([ApplicationConfig]$app, [string]$stepName) {
        $functionName = "Invoke-${stepName}_$($app.Name)"
        if(Get-Command $functionName -ErrorAction SilentlyContinue) {
            $this.Logger.Log("INFO", "Running $stepName for $($app.Name)")
            return & $functionName -Application $app
        }
        return $true
    }
    
    # Implementation methods for different package types...
    hidden [bool]DownloadWingetPackage([ApplicationConfig]$app) {
        $this.Logger.Log("DBUG", "Binary path: $($app.BinaryPath)")
        $TempBinaryPath = $($app.BinaryPath).Replace([System.IO.Path]::GetExtension($app.BinaryPath), "")
        $this.Logger.Log("INFO", "Downloading $($app.Name) from winget to $TempBinaryPath")
        
        $this.SystemOps.AddFolders($TempBinaryPath)
        $version = (Find-WinGetPackage -Id $app.ApplicationID -MatchOption Equals).Version
        $DownloadArguments = @("--version", $version,"--download-directory", "`"$TempBinaryPath`"","--accept-source-agreements","--accept-package-agreements")
        if ($app.MachineScope) {$DownloadArguments += @("--scope", "machine")}
        
        try {
            $Process = $this.SystemOps.StartProcess("winget", @("download", "--id", $app.ApplicationID) + $DownloadArguments)
            if ($Process.ExitCode -eq 0) {$this.Logger.Log("SUCCESS", "$($app.Name) v$version downloaded successfully")}
            else {$this.Logger.Log("ERROR", "Download failed with exit code $($Process.ExitCode)");return $false}
            # Move downloaded files to binary directory
            Get-ChildItem -Path $TempBinaryPath | ForEach-Object {
                $NewFileName = if($_.PSIsContainer) {"$($app.Name)_$($app.Version)_$($_.Name)"} else {"$($app.Name)_$($app.Version)$($_.Extension)"}
                $destinationPath = Join-Path -Path $this.ConfigManager.ResolvePath('binaries') -ChildPath $NewFileName
                $this.SystemOps.MoveFolder($_.FullName, $destinationPath)
            }
            Remove-Item -Path $TempBinaryPath -Recurse -Force
            return $true
        } catch {$this.Logger.Log("ERROR", "Failed to download: $_");return $false}
    }
    
    hidden [bool]DownloadDirectPackage([ApplicationConfig]$app) {
        if (-not (Test-Path $app.BinaryPath)) {
            $this.Logger.Log("INFO", "Downloading $($app.Name) from $($app.DownloadURL)")
            try {Invoke-WebRequest -Uri $app.DownloadURL -OutFile $app.BinaryPath;$this.Logger.Log("SUCCESS", "Download completed")}
            catch {$this.Logger.Log("ERROR", "Download failed: $_");return $false}
        }
        try {Copy-Item -Path $app.BinaryPath -Destination $app.StagedPath -Force;return $true}
        catch {$this.Logger.Log("ERROR", "Failed to copy to staging: $_");return $false}
    }
    
    hidden [bool]InstallWingetPackage([ApplicationConfig]$app) {
        $version = (Find-WinGetPackage -Id $app.ApplicationID -MatchOption Equals).Version
        $this.Logger.Log("INFO", "Installing $($app.Name) v$version")
        $InstallArguments = @("--accept-source-agreements","--accept-package-agreements","--force")
        if ($app.InstallerArguments) {$InstallArguments += $app.InstallerArguments}
        $ApplicationArguments = if($app.Download -and (Test-Path -Path $($app.BinaryPath).Replace([System.IO.Path]::GetExtension($app.BinaryPath), ".yaml"))) {
            @("--manifest", $($app.BinaryPath).Replace([System.IO.Path]::GetExtension($app.BinaryPath), ".yaml"))
        } else {@("--id", $app.ApplicationID)}
        try {$Process = $this.SystemOps.StartProcess("winget", @("install") + $ApplicationArguments + $InstallArguments);return $Process.ExitCode -eq 0}
        catch {$this.Logger.Log("ERROR", "Installation failed: $_");return $false}
    }
    
    hidden [bool]InstallPSModule([ApplicationConfig]$app) {
        $installParams = @{Name=$app.ModuleID;Force=$true;Confirm=$false}
        if ($app.Version -ne "latest") {$installParams.RequiredVersion = $app.Version}
        try {Install-Module @installParams;return $true}
        catch {$this.Logger.Log("ERROR", "Failed to install PS module: $_");return $false}
    }
    
    hidden [bool]InstallDirectPackage([ApplicationConfig]$app) {
        if (-not $app.StagedPath) {
            $this.Logger.Log("ERROR", "No staged path specified")
            return $false
        }
        
        $FileType = [System.IO.Path]::GetExtension($app.StagedPath)
        return switch ($FileType) {
            ".zip"
            {
                try {Expand-Archive -Path $app.StagedPath -DestinationPath $app.InstallPath -Force;$true}
                catch {$this.Logger.Log("ERROR", "Failed to extract ZIP: $_");$false}
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
            {$this.Logger.Log("ERROR", "Unsupported file type: $FileType");$false}
        }
    }

    hidden [bool]UninstallWingetPackage([ApplicationConfig]$app) {
        $UninstallArguments = @("--silent","--force","--disable-interactivity","--ignore-warnings")
        try {$Process = $this.SystemOps.StartProcess("winget", @("uninstall", "--id", $app.ApplicationID) + $UninstallArguments);return $Process.ExitCode -eq 0}
        catch {$this.Logger.Log("ERROR", "Uninstallation failed: $_");return $false}
    }
    
    hidden [bool]UninstallPSModule([ApplicationConfig]$app) {
        try {Uninstall-Module -Name $app.ModuleID -Force -AllVersions;return $true}
        catch {$this.Logger.Log("ERROR", "Failed to uninstall PS module: $_");return $false}
    }
    
    hidden [bool]UninstallDirectPackage([ApplicationConfig]$app) {
        if (-not $app.PostInstallPath) {$this.Logger.Log("ERROR", "No post-install path specified");return $false}

        $FileType = [System.IO.Path]::GetExtension($app.PostInstallPath)
        return $(switch ($FileType) {
            ".msi"
            {$Process = $this.SystemOps.StartProcess("msiexec.exe", @("/x", $app.PostInstallPath, "/qb!"));$Process.ExitCode -eq 0}
            ".exe"
            {
                if ($app.UninstallerArguments) {$Process = $this.SystemOps.StartProcess($app.PostInstallPath, $app.UninstallerArguments);return $Process.ExitCode -eq 0}
                else {Remove-Item -Path $app.InstallPath -Recurse -Force -ErrorAction SilentlyContinue; return $true}
            }
            default
            {if (Test-Path $app.InstallPath) {Remove-Item -Path $app.InstallPath -Recurse -Force -ErrorAction SilentlyContinue; return $true}}
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
