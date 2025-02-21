using namespace System.Collections
using namespace System.IO
using namespace System.Management.Automation

class ConfigManager {
    hidden [object]$Logger
    [object]$Config
    [System.Collections.ArrayList]$ValidationErrors
    
    ConfigManager([string]$configPath, [object]$logger) {
        $this.ValidationErrors = [System.Collections.ArrayList]::new()
        $this.Logger = $logger
        
        # Validate and resolve paths
        $resolvedConfigPath = [System.IO.Path]::GetFullPath($configPath)
        if (-not (Test-Path $resolvedConfigPath)) {
            $this.Logger.Log("ERRR", "Configuration file not found at: $resolvedConfigPath")
            throw "Configuration file not found"
        }
        
        $this.LoadConfig($resolvedConfigPath)
    }
    
    # Configuration methods
    [void]LoadConfig([string]$configPath) {
        try {
            $this.Config = Get-Content -Raw -Path $configPath | ConvertFrom-Json
            $this.ValidateConfig()
            $this.Logger.Log("INFO", "Configuration loaded successfully")
        }
        catch {
            $this.Logger.Log("ERRR", "Failed to load configuration: $_")
            throw
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
        [Parameter(Mandatory=$true)][string]$ConfigPath,
        [Parameter(Mandatory=$true)][object]$Logger
    )
    return [ConfigManager]::new($ConfigPath, $Logger)
}

Export-ModuleMember -Function New-ConfigManager
