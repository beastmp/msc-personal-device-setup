using namespace System.Collections
using namespace System.IO

class ProgressTracker {
    [int]$Total
    [int]$Current
    [string]$Activity
    [hashtable]$Timings = @{}
    
    ProgressTracker([string]$activity, [int]$total) {
        $this.Activity = $activity
        $this.Total = $total
        $this.Current = 0
    }
    
    [void]StartOperation([string]$name) {
        $this.Timings[$name] = @{
            StartTime = Get-Date
            EndTime = $null
            Duration = $null
        }
    }
    
    [void]CompleteOperation([string]$name) {
        $this.Timings[$name].EndTime = Get-Date
        $this.Timings[$name].Duration = $this.Timings[$name].EndTime - $this.Timings[$name].StartTime
        $this.Current++
        
        $percent = ($this.Current / $this.Total) * 100
        $status = "$name - $($this.Current) of $($this.Total) ($([math]::Round($percent))%)"
        
        Write-Progress -Activity $this.Activity -Status $status -PercentComplete $percent
    }
    
    [hashtable]GetSummary() {
        return @{
            TotalOperations = $this.Total
            CompletedOperations = $this.Current
            PercentComplete = ($this.Current / $this.Total) * 100
            Timings = $this.Timings
        }
    }
}

class LogManager {
    [string]$LogPath
    [string]$TelemetryPath
    [hashtable]$LogLevels
    [hashtable]$Metrics = @{}
    [System.Collections.ArrayList]$Events = @()
    
    # Add simple constructor for basic initialization
    LogManager() {
        $this.LogLevels = @{
            INFO = 0; SCSS = 1; ERRR = 2; WARN = 3
            DBUG = 4; VRBS = 5; PROG = 6
        }
    }
    
    # Keep existing constructor as an initialization method
    [void]Initialize([string]$logPath, [string]$telemetryPath) {
        $this.LogPath = $logPath
        $this.TelemetryPath = $telemetryPath
        
        # Ensure log directory exists
        $logDir = Split-Path -Parent $logPath
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
    }

    # Modify Log method to handle uninitialized state
    [void]Log([string]$level, [string]$message) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $color = switch ($level) {
            "SCSS" { "Green" }
            "ERRR" { "Red" }
            "WARN" { "Yellow" }
            "DBUG" { "Cyan" }
            "VRBS" { "DarkYellow" }
            "PROG" { "Magenta" }
            default { "White" }
        }
        
        Write-Host "[$timestamp] [$level] $message" -ForegroundColor $color
        
        # Only write to file if paths are initialized
        if ($this.LogPath) {
            $logEntry = @{
                Timestamp = $timestamp
                Level = $level
                Message = $message
            } | ConvertTo-Json
            
            Add-Content -Path $this.LogPath -Value $logEntry -ErrorAction SilentlyContinue
        }
    }
    
    # Add the original method as an overload
    [void]Log([string]$level, [string]$message, [hashtable]$context) {
        $this.LogWithContext($level, $message, $context)
    }
    
    # Add a private method for the full implementation
    hidden [void]LogWithContext([string]$level, [string]$message, [hashtable]$context) {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $logEntry = @{
            Timestamp = $timestamp
            Level = $level
            Message = $message
            Context = $context
        }
        
        $color = switch ($level) {
            "SCSS" { "Green" }
            "ERRR" { "Red" }
            "WARN" { "Yellow" }
            "DBUG" { "Cyan" }
            "VRBS" { "DarkYellow" }
            "PROG" { "Magenta" }
            default { "White" }
        }
        
        Write-Host "[$timestamp] [$level] $message" -ForegroundColor $color
        $logEntry | ConvertTo-Json | Add-Content -Path $this.LogPath -ErrorAction Stop
    }
    
    
    [void]TrackEvent([string]$name, [hashtable]$properties) {
        $newEvent = @{
            Timestamp = Get-Date
            Name = $name
            Properties = $properties
        }
        $this.Events.Add($newEvent)
        $newEvent | ConvertTo-Json | Add-Content -Path $this.TelemetryPath
    }
    
    [void]TrackMetric([string]$name, [double]$value) {
        if (-not $this.Metrics[$name]) {
            $this.Metrics[$name] = @()
        }
        $this.Metrics[$name] += $value
    }
    
    [hashtable]GetMetricsSummary() {
        $summary = @{}
        foreach ($metric in $this.Metrics.GetEnumerator()) {
            $summary[$metric.Key] = @{
                Average = ($metric.Value | Measure-Object -Average).Average;
                Min = ($metric.Value | Measure-Object -Minimum).Minimum;
                Max = ($metric.Value | Measure-Object -Maximum).Maximum;
                Count = $metric.Value.Count
            }
        }
        return $summary
    }
}

function New-LogManager {
    [CmdletBinding()]
    param()
    return [LogManager]::new()
}

Export-ModuleMember -Function New-LogManager