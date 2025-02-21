using namespace System.Collections
using namespace System.IO

class StateManager {
    [string]$StateFile
    [hashtable]$State = @{}

    StateManager([string]$stateFile) {
        $this.StateFile = $stateFile
        $this.LoadState()
    }

    [void]LoadState() {
        if (Test-Path $this.StateFile) {
            $this.State = Get-Content $this.StateFile | ConvertFrom-Json -AsHashtable
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
        [Parameter(Mandatory=$true)][string]$StateFile
    )
    return [StateManager]::new($StateFile)
}

Export-ModuleMember -Function New-StateManager
