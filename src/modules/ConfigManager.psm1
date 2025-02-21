using namespace System.Collections
using namespace System.IO
using namespace System.Management.Automation

class ConfigManager {
    [object]$Config
    [System.Collections.ArrayList]$ValidationErrors
    
    ConfigManager([string]$configPath) {
        $this.ValidationErrors = [System.Collections.ArrayList]::new()
        
        # Validate and resolve paths
        $resolvedConfigPath = [System.IO.Path]::GetFullPath($configPath)
        if (-not (Test-Path $resolvedConfigPath)) {
            throw "Configuration file not found at: $resolvedConfigPath"
        }
        
        $this.LoadConfig($resolvedConfigPath)
    }
    
    # Configuration methods
    [void]LoadConfig([string]$configPath) {
        try {
            $this.Config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
            $this.ValidateConfig()
        }
        catch {
            throw "Failed to load configuration: $_"
        }
    }
    
    [bool]ValidateConfig() {
        $this.ValidationErrors.Clear()
        if (-not $this.Config) {
            $this.AddValidationError("Configuration is null")
            return $false
        }

        $schema = @{
            directories = @('binaries', 'scripts', 'staging', 'install', 'postInstall', 'logs')
            files = @('softwareList')
            logging = @('fileNameFormat')
            execution = @('maxConcurrentJobs', 'jobTimeoutSeconds', 'retryCount')
            cleanup = @('removeStaging', 'removeFailedInstalls')
        }

        foreach ($section in $schema.Keys) {
            if (-not $this.Config.PSObject.Properties[$section]) {
                $this.AddValidationError("Missing section: $section")
                return $false
            }
        }
        return $true
    }

    [string]GetStatePath() {
        # Get the scripts directory and software list filename from config
        $scriptsDir = $this.ResolvePath('scripts')
        $softwareListFile = $this.Config.files.softwareList
        
        # Build the full path to the scripts directory where state.json will live
        $configDir = Split-Path -Parent (Join-Path $scriptsDir $softwareListFile)
        return Join-Path $configDir "state.json"
    }
    
    # Utility methods
    [void]AddValidationError([string]$validationError) {
        $this.ValidationErrors.Add($validationError) | Out-Null
    }
    
    [array]GetValidationErrors() {
        return $this.ValidationErrors
    }
    
    [string]ResolvePath([string]$pathKey) {
        $path = $this.Config.directories.$pathKey
        if (-not $path) {
            throw "Path key not found in configuration: $pathKey"
        }
        
        # Expand environment variables and resolve to absolute path
        $expandedPath = [System.Environment]::ExpandEnvironmentVariables($path)
        return [System.IO.Path]::GetFullPath($expandedPath)
    }
}

function New-ConfigManager {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ConfigPath
    )
    return [ConfigManager]::new($ConfigPath)
}

Export-ModuleMember -Function New-ConfigManager
