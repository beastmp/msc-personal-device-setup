using namespace System.Collections
using namespace System.IO

$script:InitializationLog = @()

class SystemOperations {
    # Add Logger property
    hidden [object]$Logger

    # File operation properties
    [string]$BinariesDirectory
    [string]$StagingDirectory
    [string]$InstallDirectory
    
    # Process management properties
    [int]$DefaultTimeout = 1800 # 30 minutes
    [int]$RetryCount
    [int]$RetryDelay

    [int]$MaxConcurrentJobs
    [int]$JobTimeout

    [bool]$RetryEnabled
    [bool]$ParallelEnabled

    hidden [int]$CacheRetentionDays = 30
    
    # Update constructor to accept Logger and Config
    SystemOperations([string]$binDir, [string]$stagingDir, [string]$installDir, [object]$logger, [object]$config) {
        $this.BinariesDirectory = $binDir
        $this.StagingDirectory = $stagingDir
        $this.InstallDirectory = $installDir
        $this.Logger = $logger
        $this.RetryEnabled = $config.execution.retry.enabled
        $this.ParallelEnabled = $config.execution.parallelProcessing.enabled
        $this.MaxConcurrentJobs = $config.execution.parallelProcessing.maxConcurrentJobs
        $this.JobTimeout = $config.execution.parallelProcessing.jobTimeoutSeconds
        $this.RetryCount = $config.execution.retry.maxAttempts
        $this.RetryDelay = $config.execution.retry.delaySeconds
    }
    
    # File Operations
    [bool]AddFolders([string]$DirPath) {
        if (-Not (Test-Path -Path $DirPath)) {
            try {
                New-Item -ItemType Directory -Path $DirPath -Force | Out-Null
                $this.Logger.Log("VRBS", "$DirPath directory created successfully")
                return $true
            } catch {$this.Logger.Log("ERRR", "Unable to create $DirPath directory: $_");return $false}
        }
        return $true
    }
    
    [bool]AddSymLink([string]$SourcePath, [string]$TargetPath) {
        $this.AddFolders($TargetPath)
        $this.AddFolders($(Split-Path $SourcePath -Parent))
        try {
            cmd "/c" mklink "/J" $SourcePath $TargetPath
            $this.Logger.Log("VRBS", "Created symbolic link from $SourcePath to $TargetPath")
            return $true
        } catch {$this.Logger.Log("ERRR", "Failed to create symbolic link: $_");return $false}
    }
    
    # Add basic move folder operation
    [bool]MoveFolder([string]$source, [string]$destination) {
        try {
            Move-Item -Path $source -Destination $destination -Force
            $this.Logger.Log("VRBS", "Moved $source to $destination")
            return $true
        } catch {$this.Logger.Log("ERRR", "Failed to move $source to ${destination}: $_");return $false}
    }

    # Specialized move for zip extractions
    [bool]MoveFolder([string]$InstallDir, [string]$Version, [string]$Prefix) {
        $sourceDir = Join-Path $InstallDir "${Prefix}${Version}"
        $this.Logger.Log("VRBS", "Moving contents from $sourceDir to $InstallDir")
        try {
            Get-ChildItem -Path $sourceDir | Move-Item -Destination $InstallDir -Force
            $this.Logger.Log("VRBS", "Moved contents to $InstallDir")
            Remove-Item -Path $sourceDir -Force -Recurse
            $this.Logger.Log("VRBS", "Removed source directory $sourceDir")
            return $true
        } catch {$this.Logger.Log("ERRR", "Failed to move contents from $sourceDir to $InstallDir`: $_");return $false}
    }
    
    [bool]ValidatePath([string]$path) {
        if([string]::IsNullOrWhiteSpace($path)){$this.Logger.Log("ERRR", "Path cannot be null or empty");return $false}
        try {
            $resolvedPath = [System.IO.Path]::GetFullPath($path)
            if(-not(Test-Path $resolvedPath -IsValid)){$this.Logger.Log("ERRR", "Invalid path format: $path");return $false}
            $parent = Split-Path $resolvedPath -Parent
            if(-not(Test-Path $parent)){if(-not $this.AddFolders($parent)){return $false}}
            return $true
        } catch {$this.Logger.Log("ERRR", "Path validation failed: $_");return $false}
    }

    # Update ValidateFileHash method signature to make Algorithm optional
    [bool]ValidateFileHash([string]$FilePath,[string]$ExpectedHash){return $this.ValidateFileHashWithAlgorithm($FilePath,$ExpectedHash,'SHA256')}

    # Add new method with all parameters
    hidden [bool]ValidateFileHashWithAlgorithm([string]$FilePath,[string]$ExpectedHash,[string]$Algorithm){
        try{
            if (-not (Test-Path $FilePath)) {$this.Logger.Log("ERRR", "File not found: $FilePath");return $false}
            $actualHash = (Get-FileHash -Path $FilePath -Algorithm $Algorithm).Hash
            $result = $actualHash -eq $ExpectedHash
            if ($result) {$this.Logger.Log("VRBS", "Hash validation successful for $FilePath")}
            else {$this.Logger.Log("WARN", "Hash mismatch for $FilePath. Expected: $ExpectedHash, Got: $actualHash")}
            return $result
        } catch {$this.Logger.Log("ERRR", "Hash validation failed: $_");return $false}
    }

    # Process Management
    [object]InvokeWithRetry([scriptblock]$ScriptBlock) {
        if (-not $this.RetryEnabled) { return & $ScriptBlock }
        return $this.InvokeWithRetry($ScriptBlock, "operation", $this.RetryCount, $this.RetryDelay)
    }
    
    [object]InvokeWithRetry([scriptblock]$ScriptBlock, [string]$Activity) {
        return $this.InvokeWithRetry($ScriptBlock, $Activity, $this.RetryCount, $this.RetryDelay)
    }
    
    [object]InvokeWithRetry([scriptblock]$ScriptBlock, [string]$Activity, [int]$MaxAttempts, [int]$DelaySeconds) {
        $attempt = 1
        while ($attempt -le $MaxAttempts) {
            try {
                if($attempt -gt 1){$this.Logger.Log("WARN", "Retrying $Activity (Attempt $attempt of $MaxAttempts)...");Start-Sleep -Seconds $DelaySeconds}
                return & $ScriptBlock
            } catch {
                if ($attempt -eq $MaxAttempts) {$this.Logger.Log("ERRR", "Failed to $Activity after $MaxAttempts attempts: $_");throw}
                $this.Logger.Log("WARN", "Attempt $attempt failed: $_")
                $attempt++
            }
        }
        return $null
    }

    [array]InvokeParallel([scriptblock]$ScriptBlock, [array]$Items) {
        if(-not $this.ParallelEnabled){$results=@();foreach($item in $Items){$results += & $ScriptBlock $item};return $results}
        $jobs = @()
        $results = @()
        $runspacePool = [runspacefactory]::CreateRunspacePool(1, $this.MaxConcurrentJobs)
        $runspacePool.Open()
        foreach ($item in $Items) {
            $powerShell = [powershell]::Create().AddScript($ScriptBlock).AddArgument($item)
            $powerShell.RunspacePool = $runspacePool
            $jobs += @{PowerShell=$powerShell;Handle=$powerShell.BeginInvoke();Item=$item;StartTime=Get-Date}
        }
        while ($jobs.Where({ -not $_.Handle.IsCompleted })) {
            foreach ($job in $jobs.Where({ -not $_.Handle.IsCompleted })) {
                if ((Get-Date) - $job.StartTime -gt [TimeSpan]::FromSeconds($this.JobTimeout)) {
                    $this.Logger.Log("ERRR", "Operation timeout for item: $($job.Item)")
                    $job.PowerShell.Stop()
                    $job.Handle.IsCompleted = $true
                }
            }
            Start-Sleep -Seconds 1
        }
        foreach ($job in $jobs) {
            try {$results += $job.PowerShell.EndInvoke($job.Handle)}
            catch {$this.Logger.Log("ERRR", "Error in parallel operation: $_")}
            finally {$job.PowerShell.Dispose()}
        }
        $runspacePool.Close()
        $runspacePool.Dispose()
        return $results
    }

    [object]StartProcess([string]$Command,[string[]]$Arguments){return $this.StartProcess($Command, $Arguments, 0)}
    
    [object]StartProcess([string]$Command, [string[]]$Arguments, [int]$Timeout = 0) {
        if($Timeout -eq 0){$Timeout=$this.DefaultTimeout}
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $Command
        $pinfo.RedirectStandardError = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true
        $pinfo.Arguments = $Arguments -join ' '
        
        $this.Logger.Log("DBUG", "Command: $($pinfo.FileName) $($pinfo.Arguments)")
        $this.Logger.Log("DBUG", "PowerShell Command: Start-Process -FilePath $($pinfo.FileName) -ArgumentList $($pinfo.Arguments) -NoNewWindow -Wait")
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $pinfo
        $script:outputData = ""
        $script:errorData = ""
        
        $outputEvent = Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -Action {if($EventArgs.Data){$script:outputData += "$($EventArgs.Data)`n"}}
        $errorEvent = Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -Action {if($EventArgs.Data){$script:errorData += "$($EventArgs.Data)`n"}}
        
        $process.Start() | Out-Null
        $this.Logger.Log("DBUG", "ProcessID: $($process.Id)")
        $process.BeginOutputReadLine()
        $process.BeginErrorReadLine()
        
        if (-not $process.WaitForExit($Timeout * 1000)) {
            $process.Kill()
            $this.Logger.Log("ERRR", "Process $Command timed out after $Timeout seconds")
            Unregister-Event -SourceIdentifier $outputEvent.Name
            Unregister-Event -SourceIdentifier $errorEvent.Name
            throw "Process $Command timed out after $Timeout seconds"
        }
        Unregister-Event -SourceIdentifier $outputEvent.Name
        Unregister-Event -SourceIdentifier $errorEvent.Name
        $this.Logger.Log("DBUG", "ExitCode: $($process.ExitCode)")
        $this.Logger.Log("DBUG", "StandardOutput: $script:outputData")
        $this.Logger.Log("DBUG", "StandardError: $script:errorData")
        return @{ExitCode=$process.ExitCode;StandardOutput=$script:outputData.Trim();StandardError=$script:errorData.Trim()}
    }
    
    [void]KillProcess([string]$ProcessName) {
        $process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        if ($process) {$process | Stop-Process -Force;$this.Logger.Log("VRBS", "Killed process: $ProcessName")}
    }

    [bool]IsProcessRunning([string]$processName){return $null -ne (Get-Process -Name $processName -ErrorAction SilentlyContinue)}

    # Environment Management
    [bool]SetEnvironmentVariable([string]$Name, [string]$Value) {
        try {
            [System.Environment]::SetEnvironmentVariable($Name, $Value, [System.EnvironmentVariableTarget]::Machine)
            $this.Logger.Log("VRBS", "Environment variable $Name set to $Value")
            return $true
        } catch {$this.Logger.Log("ERRR", "Unable to set environment variable $Name to ${Value}: $_");return $false}
    }

    [bool]AddToPath([string]$Value) {
        $envPath = [System.Environment]::GetEnvironmentVariable("Path", [System.EnvironmentVariableTarget]::Machine)
        if ($envPath -notlike "*$Value*") {
            try {
                [System.Environment]::SetEnvironmentVariable("Path", "$envPath;$Value", [System.EnvironmentVariableTarget]::Machine)
                $this.Logger.Log("VRBS", "Added $Value to PATH")
                return $true
            } catch {$this.Logger.Log("ERRR", "Unable to add $Value to PATH: $_");return $false}
        }
        return $true
    }

    [bool] InstallRequiredPackageProvider([string]$ProviderName) {
        if(-not (Get-PackageProvider -Name $ProviderName -ErrorAction SilentlyContinue)) {
            $this.Logger.Log("INFO","Installing $ProviderName package provider...")
            try {
                Install-PackageProvider -Name $ProviderName -Force -Confirm:$false | Out-Null
                $this.Logger.Log("INFO","$ProviderName package provider installed successfully")
                return $true
            }
            catch {
                $this.Logger.Log("ERRR","Failed to install $ProviderName package provider: $_")
                return $false
            }
        }
        return $true
    }

    [bool] InstallWingetProvider() {
        if(-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            $this.Logger.Log("INFO","Installing WinGet PowerShell module from PSGallery...")
            if(-not ($this.InstallRequiredPackageProvider("NuGet"))) {
                $this.Logger.Log("ERRR","Failed to install NuGet package provider")
                return $false
            }
            try {
                Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery -Confirm:$false | Out-Null
                $this.Logger.Log("INFO","Using Repair-WinGetPackageManager cmdlet to bootstrap WinGet...")
                Repair-WinGetPackageManager -Force
                Write-Progress -Completed -Activity "make progress bar disappear"
                $this.Logger.Log("INFO","WinGet installation completed")
            }
            catch {
                $this.Logger.Log("ERRR","Failed to install WinGet: $_")
                return $false
            }
        }
        return $true
    }

    [void]CleanupCache([int]$daysToKeep = 30) {
        $cutoff = (Get-Date).AddDays(-$daysToKeep)
        $cacheFiles = Get-ChildItem -Path $this.BinariesDirectory -Filter "*.cache"
        
        foreach ($file in $cacheFiles) {
            try {
                $cacheContent = Get-Content $file.FullName | ConvertFrom-Json
                $cacheDate = [DateTime]::Parse($cacheContent.DateTime)
                if ($cacheDate -lt $cutoff) {
                    $this.Logger.Log("VRBS", "Removing old cache file: $($file.Name)")
                    Remove-Item $file.FullName -Force
                    $binaryPath = $file.FullName.Replace(".cache", "")
                    if (Test-Path $binaryPath) {
                        $this.Logger.Log("VRBS", "Removing associated binary: $($binaryPath)")
                        Remove-Item $binaryPath -Force
                    }
                }
            }
            catch {
                $this.Logger.Log("ERRR", "Failed to process cache file $($file.Name): $_")
            }
        }
    }

    [void]SaveToCache([string]$key, [string]$filePath) {
        $cacheKey = [System.IO.Path]::GetFileNameWithoutExtension($key)
        $cachePath = Join-Path $this.BinariesDirectory "$cacheKey.cache"
        $hash = (Get-FileHash -Path $filePath).Hash
        @{
            Hash = $hash
            DateTime = Get-Date -Format "o"
            FilePath = $filePath
        } | ConvertTo-Json | Set-Content $cachePath
    }

    [bool]ValidateCache([string]$key, [string]$filePath) {
        $cacheKey = [System.IO.Path]::GetFileNameWithoutExtension($key)
        $cachePath = Join-Path $this.BinariesDirectory "$cacheKey.cache"
        
        if (Test-Path $cachePath) {
            try {
                $cached = Get-Content $cachePath | ConvertFrom-Json
                return $this.ValidateFileHash($filePath, $cached.Hash)
            }
            catch {
                $this.Logger.Log("ERRR", "Failed to validate cache: $_")
                return $false
            }
        }
        return $false
    }
}

# Add module initialization script
$InitializationScript = {
    # Create temporary logger for initialization
    $tempLogger = [PSCustomObject]@{
        Log = {
            param($Level, $Message)
            $script:InitializationLog += "[$(Get-Date -f 'yyyyMMdd_HHmmss')] [$Level] $Message"
        }
    }

    # Create temporary SystemOperations instance just for initialization
    $tempSysOps = [SystemOperations]::new("", "", "", $tempLogger, @{
        execution = @{
            retry = @{ enabled = $true; maxAttempts = 3; delaySeconds = 5 }
            parallelProcessing = @{ enabled = $true; maxConcurrentJobs = 3; jobTimeoutSeconds = 300 }
        }
    })

    # Silently install required components
    try {
        if (-not $tempSysOps.InstallRequiredPackageProvider("NuGet")) {
            Write-Warning "Failed to install NuGet provider during module initialization"
        }
        if (-not $tempSysOps.InstallWingetProvider()) {
            Write-Warning "Failed to install WinGet during module initialization"
        }
    }
    catch {
        Write-Warning "Error during SystemOperations initialization: $_"
    }
}

# Execute initialization
. $InitializationScript

function New-SystemOperations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$BinDir,
        [Parameter(Mandatory=$true)][string]$StagingDir,
        [Parameter(Mandatory=$true)][string]$InstallDir,
        [Parameter(Mandatory=$true)][object]$Logger,
        [Parameter(Mandatory=$true)][object]$Config
    )
    
    return [SystemOperations]::new($BinDir, $StagingDir, $InstallDir, $Logger, $Config)
}

Export-ModuleMember -Function New-SystemOperations
