using namespace System.Collections
using namespace System.IO

class StateManager {
    [string]$StateFile
    [hashtable]$State = @{}
    hidden [object]$Logger

    StateManager([string]$stateFile, [object]$logger) {
        $this.StateFile = $stateFile
        $this.Logger = $logger
        $this.LoadState()
    }

    [void]LoadState() {
        if (Test-Path $this.StateFile) {
            try {
                $jsonContent = Get-Content $this.StateFile | ConvertFrom-Json
                # Convert PSCustomObject to hashtable
                $this.State = @{}
                if ($jsonContent) {
                    $jsonContent.PSObject.Properties | ForEach-Object {
                        $this.State[$_.Name] = $_.Value
                    }
                }
                $this.Logger.Log("VRBS", "State loaded successfully from $($this.StateFile)")
            }
            catch {
                $this.Logger.Log("ERRR", "Failed to load state: $_")
            }
        }
    }

    [void]SaveState() {
        $this.State | ConvertTo-Json | Set-Content $this.StateFile
    }

    [void]SetApplicationState([string]$appName, [string]$version, [object]$state) {
        $key = "$appName-$version"
        $this.State[$key] = $state
        $this.SaveState()
    }

    [object]GetApplicationState([string]$appName, [string]$version) {
        return $this.State["$appName-$version"]
    }

    [void]ValidateApplication([object]$app) {
        # Add validation logic here
        return
    }

    [void]CleanupOldStates([int]$daysToKeep) {
        $cutoff = (Get-Date).AddDays(-$daysToKeep)
        $keysToRemove = @()
        
        foreach ($entry in $this.State.GetEnumerator()) {
            if ($entry.Value.LastAccessed -lt $cutoff) {
                $keysToRemove += $entry.Key
            }
        }
        
        foreach ($key in $keysToRemove) {
            $this.State.Remove($key)
        }
        
        $this.SaveState()
    }
}

# Create function to return new instance
function New-StateManager {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$StateFile,
        [Parameter(Mandatory=$true)][object]$Logger
    )
    return [StateManager]::new($StateFile, $Logger)
}

Export-ModuleMember -Function New-StateManager
