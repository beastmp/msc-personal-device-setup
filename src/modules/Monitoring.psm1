using namespace System.Collections
using namespace System.IO

class ProgressTracker {
    [int]$Total
    [int]$Current
    [string]$Activity
    [hashtable]$Timings = @{}
    
    ProgressTracker([string]$activity,[int]$total){$this.Activity=$activity;$this.Total=$total;$this.Current=0}
    
    [void]StartOperation([string]$name){$this.Timings[$name]=@{StartTime=Get-Date;EndTime=$null;Duration=$null}}
    
    [void]CompleteOperation([string]$name) {
        $this.Timings[$name].EndTime = Get-Date
        $this.Timings[$name].Duration = $this.Timings[$name].EndTime - $this.Timings[$name].StartTime
        $this.Current++
        $percent = ($this.Current / $this.Total) * 100
        $status = "$name - $($this.Current) of $($this.Total) ($([math]::Round($percent))%)"
        Write-Progress -Activity $this.Activity -Status $status -PercentComplete $percent
    }
    
    [hashtable]GetSummary(){return @{TotalOperations=$this.Total;CompletedOperations=$this.Current;PercentComplete=($this.Current / $this.Total) * 100;Timings=$this.Timings}}
}

class LogManager {
    [string]$LogPath
    [string]$TelemetryPath
    [hashtable]$LogLevels
    [hashtable]$Metrics = @{}
    [System.Collections.ArrayList]$Events = @()
    [string]$LogFileFormat
    
    # Add simple constructor for basic initialization
    LogManager() {
        $this.LogLevels=@{INFO=0;SCSS=1;ERRR=2;WARN=3;DBUG=4;VRBS=5;PROG=6}
        $this.LogFileFormat = "{LogType}_{ScriptName}_{Action}_{TargetName}_{Version}_{DateTime}.log"
        if (-not $PSBoundParameters.ContainsKey('Verbose')){$VerbosePreference = $PSCmdlet.GetVariableValue('VerbosePreference')}
        if (-not $PSBoundParameters.ContainsKey('Debug')){$DebugPreference = $PSCmdlet.GetVariableValue('DebugPreference')}
    }
    
    # Keep existing constructor as an initialization method
    [void]Initialize([string]$logPath, [string]$telemetryPath) {
        $this.LogPath = $logPath
        $this.TelemetryPath = $telemetryPath
        $logDir = Split-Path -Parent $logPath
        if(-not(Test-Path $logDir)){New-Item -ItemType Directory -Path $logDir -Force | Out-Null}
    }

    [void]Log([string]$level, [string]$message){$this.Log($level,$message,$null)}
    [void]Log([string]$level, [string]$message, [hashtable]$context = $null) {
        # if (-not $PSBoundParameters.ContainsKey('Verbose')){$VerbosePreference = $PSCmdlet.GetVariableValue('VerbosePreference')}
        # if (-not $PSBoundParameters.ContainsKey('Debug')){$DebugPreference = $PSCmdlet.GetVariableValue('DebugPreference')}
        # if ($level -eq "VRBS" -and -not $VerbosePreference.ToString().Equals('Continue')) { return }
        # if ($level -eq "DBUG" -and -not $DebugPreference.ToString().Equals('Continue')) { return }
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $color = switch($level){"SCSS"{"Green"};"ERRR"{"Red"};"WARN"{"Yellow"};"DBUG"{"Cyan"};"VRBS"{"DarkYellow"};"PROG"{"Magenta"};default{"White"}}
        Write-Host "[$timestamp] [$level] $message" -ForegroundColor $color
        if ($this.LogPath) {
            $logEntry = @{Timestamp=$timestamp;Level=$level;Message=$message;}
            if ($context) { $logEntry.Context = $context }
            $logEntry | ConvertTo-Json | Add-Content -Path $this.LogPath -ErrorAction SilentlyContinue
        }
    }
   
    # Add method to set custom format
    [void]SetLogFileFormat([string]$format) {
        $this.LogFileFormat = $format
    }

    [string]GetLogFileName([string]$LogType, [string]$Action, [string]$TargetName, [string]$Version, [string]$ScriptName) {
        $DateTime = Get-Date -f 'yyyyMMddHHmmss'
        $replacements = @{"{LogType}"=$LogType;"{ScriptName}"=$ScriptName;"{Action}"=$Action;"{TargetName}"=$TargetName;"{Version}"=$Version;"{DateTime}"=$DateTime}
        $fileName = $this.LogFileFormat
        foreach($key in $replacements.Keys){$fileName=$fileName.Replace($key, $replacements[$key])}
        $this.Logger.Log("DBUG","Log file name generated: $fileName")
        return $fileName
    }
    
    [void]TrackEvent([string]$name,[hashtable]$properties) {
        $newEvent=@{Timestamp=Get-Date;Name=$name;Properties=$properties}
        $this.Events.Add($newEvent)
        $newEvent | ConvertTo-Json | Add-Content -Path $this.TelemetryPath
    }
    
    [void]TrackMetric([string]$name, [double]$value) {if(-not $this.Metrics[$name]){$this.Metrics[$name]=@()};$this.Metrics[$name] += $value}
    
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

function New-LogManager {[CmdletBinding()]param();return [LogManager]::new()}

Export-ModuleMember -Function New-LogManager