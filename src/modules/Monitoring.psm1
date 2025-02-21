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
    
    LogManager([string]$logPath, [string]$telemetryPath) {
        $this.LogPath = $logPath
        $this.TelemetryPath = $telemetryPath
        $this.LogLevels = @{
            INFO = 0; SCSS = 1; ERRR = 2; WARN = 3
            DBUG = 4; VRBS = 5; PROG = 6
        }
    }
    
    [void]Log([string]$level, [string]$message, [hashtable]$context = @{}) {
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
        $logEntry | ConvertTo-Json | Add-Content -Path $this.LogPath
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
                Average = ($metric.Value | Measure-Object -Average).Average
                Min = ($metric.Value | Measure-Object -Minimum).Minimum
                Max = ($metric.Value | Measure-Object -Maximum).Maximum
                Count = $metric.Value.Count
            }
        }
        return $summary
    }
}

function New-LogManager {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$LogPath,
        [Parameter(Mandatory=$true)][string]$TelemetryPath
    )
    return [LogManager]::new($LogPath, $TelemetryPath)
}

Export-ModuleMember -Function New-LogManager
