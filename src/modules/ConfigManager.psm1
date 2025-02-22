using namespace System.Collections
using namespace System.IO
using namespace System.Management.Automation

class ConfigManager {
    hidden [object]$Logger
    [object]$Config
    [System.Collections.ArrayList]$ValidationErrors
    
    ConfigManager([string]$configPath,[object]$logger){
        $this.ValidationErrors = [System.Collections.ArrayList]::new()
        $this.Logger = $logger
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
        catch {$this.Logger.Log("ERRR", "Failed to load configuration: $_");throw}
    }
    
    [bool]ValidateConfig(){
        $this.ValidationErrors.Clear()
        if (-not $this.Config) {$this.AddValidationError("Configuration is null");return $false}
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
        $scriptsDir = $this.ResolvePath('scripts')
        $softwareListFile = $this.Config.files.softwareList
        $configDir = Split-Path -Parent (Join-Path $scriptsDir $softwareListFile)
        return Join-Path $configDir "state.json"
    }
    
    # Utility methods
    [void]AddValidationError([string]$validationError){$this.ValidationErrors.Add($validationError) | Out-Null}
    
    [array]GetValidationErrors(){return $this.ValidationErrors}
    
    [string]ResolvePath([string]$pathKey) {
        $path=$this.Config.directories.$pathKey
        if(-not $path){throw "Path key not found in configuration: $pathKey"}
        $expandedPath = [System.Environment]::ExpandEnvironmentVariables($path)
        return [System.IO.Path]::GetFullPath($expandedPath)
    }

    [object]GetSoftwareList([string]$dirPath, [string]$fileName) {
        $this.Logger.Log("INFO", "Getting software list from: $dirPath\$fileName")
        $softwareListPath = Join-Path $dirPath $fileName
        
        if (-not (Test-Path $softwareListPath)) {
            $this.Logger.Log("ERRR", "Software list JSON file not found at $softwareListPath")
            return $null
        }
        
        try {
            $softwareList = Get-Content -Raw -Path $softwareListPath | ConvertFrom-Json
            $this.Logger.Log("SCSS", "Software list successfully loaded")
            return $softwareList
        }
        catch {
            $this.Logger.Log("ERRR", "Unable to load software list")
            return $null
        }
    }

    [object]SaveSoftwareListApplication([string]$dirPath, [string]$fileName, [object]$application) {
        $this.Logger.Log("INFO", "Saving software list to: $dirPath\$fileName")
        $softwareListPath = Join-Path $dirPath $fileName
        
        if (-not (Test-Path $softwareListPath)) {
            $this.Logger.Log("ERRR", "Software list JSON file not found at $softwareListPath")
            return $null
        }
        
        try {
            $softwareList = Get-Content -Raw -Path $softwareListPath | ConvertFrom-Json
            $softwareList | Where-Object { 
                $_.Name -eq $application.Name -and $_.Version -eq $application.Version 
            } | ForEach-Object {
                $this.Logger.Log("DBUG", "Updating application: $($_.Name)")
                $_.Download = $application.Download
                $_.Install = $application.Install
                $_.MachineScope = $application.MachineScope
                $_.InstallationType = $application.InstallationType
                $_.ApplicationID = $application.ApplicationID
                $_.DownloadURL = $application.DownloadURL
                $_.ProcessID = $application.ProcessID
                $_.InstallerArguments = $application.InstallerArguments
                $_.UninstallerArguments = $application.UninstallerArguments
            }
            
            $softwareList | ConvertTo-Json -Depth 10 | Set-Content -Path $softwareListPath
            $this.Logger.Log("INFO", "Software list successfully updated and saved")
            return $softwareList
        }
        catch {
            $this.Logger.Log("ERRR", "Unable to save software list: $_")
            $this.Logger.Log("DBUG", "Error: $_")
            return $null
        }
    }
}

function New-ConfigManager{[CmdletBinding()]param([Parameter(Mandatory=$true)][string]$ConfigPath,[Parameter(Mandatory=$true)][object]$Logger)
    return [ConfigManager]::new($ConfigPath, $Logger)
}

Export-ModuleMember -Function New-ConfigManager
