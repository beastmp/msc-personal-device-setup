using namespace System.Collections
using namespace System.IO

class SystemOperations {
    # File operation properties
    [string]$BinariesDirectory
    [string]$StagingDirectory
    [string]$InstallDirectory
    
    # Process management properties
    [int]$DefaultTimeout = 300
    [int]$RetryCount = 3
    [int]$RetryDelay = 10
    
    SystemOperations([string]$binDir, [string]$stagingDir, [string]$installDir) {
        $this.BinariesDirectory = $binDir
        $this.StagingDirectory = $stagingDir
        $this.InstallDirectory = $installDir
    }
    
    # File Operations
    [bool]AddFolders([string]$DirPath) {
        if (-Not (Test-Path -Path $DirPath)) {
            try {
                New-Item -ItemType Directory -Path $DirPath -Force | Out-Null
                Write-Verbose "$DirPath directory created successfully"
                return $true
            }
            catch {
                Write-Error "Unable to create $DirPath directory"
                return $false
            }
        }
        return $true
    }
    
    [bool]AddSymLink([string]$SourcePath, [string]$TargetPath) {
        $this.AddFolders($TargetPath)
        $this.AddFolders($(Split-Path $SourcePath -Parent))
        
        try {
            cmd "/c" mklink "/J" $SourcePath $TargetPath
            return $true
        }
        catch {
            Write-Error "Unable to create symbolic link from $SourcePath to $TargetPath"
            return $false
        }
    }
    
    [bool]MoveFolder([string]$source, [string]$destination) {
        try {
            Move-Item -Path $source -Destination $destination -Force
            return $true
        }
        catch {
            Write-Error "Failed to move $source to $destination"
            return $false
        }
    }
    
    [bool]ValidatePath([string]$path) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            Write-Error "Path cannot be null or empty"
            return $false
        }
        
        try {
            $resolvedPath = [System.IO.Path]::GetFullPath($path)
            if (-not (Test-Path $resolvedPath -IsValid)) {
                Write-Error "Invalid path format: $path"
                return $false
            }
            
            $parent = Split-Path $resolvedPath -Parent
            if (-not (Test-Path $parent)) {
                if (-not $this.AddFolders($parent)) {
                    return $false
                }
            }
            return $true
        }
        catch {
            Write-Error "Path validation failed: $_"
            return $false
        }
    }

    # Process Management
    [object]InvokeWithRetry([scriptblock]$ScriptBlock, [string]$Activity) {
        $attempt = 1
        while ($attempt -le $this.RetryCount) {
            try {
                if ($attempt -gt 1) {
                    Write-Warning "Retrying $Activity (Attempt $attempt of $($this.RetryCount))..."
                }
                return & $ScriptBlock
            }
            catch {
                if ($attempt -eq $this.RetryCount) {
                    throw "Failed to $Activity after $($this.RetryCount) attempts: $_"
                }
                Start-Sleep -Seconds $this.RetryDelay
                $attempt++ 
            }
        }
        return $null
    }
    
    [object]StartProcess([string]$Command, [string[]]$Arguments, [int]$Timeout = 0) {
        if ($Timeout -eq 0) { $Timeout = $this.DefaultTimeout }
        
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $Command
        $pinfo.RedirectStandardError = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true
        $pinfo.Arguments = $Arguments -join ' '
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $pinfo
        $outputData = ""
        $errorData = ""
        
        $process.OutputDataReceived += { param($s, $e) if ($e.Data) { $outputData += "$($e.Data)`n" } }
        $process.ErrorDataReceived += { param($s, $e) if ($e.Data) { $errorData += "$($e.Data)`n" } }
        
        $process.Start() | Out-Null
        $process.BeginOutputReadLine()
        $process.BeginErrorReadLine()
        
        if (-not $process.WaitForExit($Timeout * 1000)) {
            $process.Kill()
            throw "Process $Command timed out after $Timeout seconds"
        }
        
        return @{
            ExitCode = $process.ExitCode
            StandardOutput = $outputData.Trim()
            StandardError = $errorData.Trim()
        }
    }
    
    [void]KillProcess([string]$ProcessName) {
        $process = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        if ($process) {
            $process | Stop-Process -Force
            Write-Verbose "Killed process: $ProcessName"
        }
    }

    [bool]IsProcessRunning([string]$processName) {
        return $null -ne (Get-Process -Name $processName -ErrorAction SilentlyContinue)
    }
}

function New-SystemOperations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$BinDir,
        [Parameter(Mandatory=$true)][string]$StagingDir,
        [Parameter(Mandatory=$true)][string]$InstallDir
    )
    return [SystemOperations]::new($BinDir, $StagingDir, $InstallDir)
}

Export-ModuleMember -Function New-SystemOperations
