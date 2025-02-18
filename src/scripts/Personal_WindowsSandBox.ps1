    [CmdletBinding()]
    param (
        [string]$SandboxConfigPath = "C:\Config\sandbox_config.wsb",
        [string]$HostFolderPath = "C:\Sandbox",
        [string]$SandboxFolderPath = "C:\Temp",
        [switch]$EnableNetworking = $true,
        [switch]$EnableVGPU = $true,
        [switch]$RefreshMappedFolder,
        [int]$MemoryInGB = 8,
        [int]$vCPUs = 4
    )

    Write-Host "[INFO] Initializing Windows Sandbox environment..." -ForegroundColor Cyan

function Test-AdminPrivileges {
    $currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Elevate-AdminPrivileges {
    Write-Host "[INFO] Elevating to admin privileges..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
}

function Validate-SandboxFeature {
    $sandboxFeature = Get-WindowsOptionalFeature -Online -FeatureName "Containers-DisposableClientVM"
    if ($sandboxFeature.State -ne "Enabled") {
        Write-Host "[ERROR] Windows Sandbox feature is not enabled. Enabling it now..." -ForegroundColor Yellow
        Enable-WindowsOptionalFeature -Online -FeatureName "Containers-DisposableClientVM" -All -NoRestart
        Write-Host "[WARNING] Please restart your computer to complete Windows Sandbox installation" -ForegroundColor Yellow
        throw "Sandbox feature not enabled"
    }
}

function Validate-SandboxExecutable {
    $sandboxPath = "C:\Windows\System32\WindowsSandbox.exe"
    if (-not (Test-Path $sandboxPath)) {
        Write-Host "[ERROR] Windows Sandbox executable not found at: $sandboxPath" -ForegroundColor Red
        throw "Sandbox executable not found"
    }
}

function Remove-ExistingMappedFolder {
    param (
        [string]$HostFolderPath
    )
    if (Test-Path $HostFolderPath) {
        Remove-Item -Path $HostFolderPath -Recurse -Force
        Write-Host "[INFO] Removed existing mapped folder: $HostFolderPath" -ForegroundColor Yellow
    }
}

function Create-MappedFolder {
    param (
        [string]$HostFolderPath
    )
    New-Item -ItemType Directory -Path $HostFolderPath -Force | Out-Null
    Write-Host "[INFO] Created mapped folder: $HostFolderPath" -ForegroundColor Green
}

function Create-ScriptsFolder {
    param (
        [string]$HostFolderPath
    )
    $ScriptsFolder = Join-Path $HostFolderPath "Scripts"
    New-Item -ItemType Directory -Path $ScriptsFolder -Force | Out-Null
    Write-Host "[INFO] Created Scripts folder: $ScriptsFolder" -ForegroundColor Green
}

function Copy-RequiredFiles {
    param (
        [string]$ScriptsFolder
    )
    $filesToCopy = @(
        "$PSScriptRoot\Personal_DeviceSetup.ps1",
        "$PSScriptRoot\Personal_ToolSetup.ps1", 
        "$PSScriptRoot\personal_softwarelist.json",
        "C:\Users\beastmp\OneDrive\Downloads\ussf\ussf.exe"
    )
    foreach ($file in $filesToCopy) {
        Copy-Item -Path $file -Destination $ScriptsFolder -Force
    }
}

function Create-SandboxConfig {
    param (
        [string]$SandboxConfigPath,
        [string]$HostFolderPath,
        [string]$SandboxFolderPath,
        [switch]$EnableVGPU,
        [switch]$EnableNetworking,
        [int]$MemoryInGB,
        [int]$vCPUs
    )

    return @"
<Configuration>
    <VGpu>$($EnableVGPU.ToString().ToLower())</VGpu>
    <Networking>$($EnableNetworking.ToString().ToLower())</Networking>
    <MemoryInMB>$($MemoryInGB * 1024)</MemoryInMB>
    <vCPU>$vCPUs</vCPU>
    <MappedFolders>
        <MappedFolder>
            <HostFolder>$HostFolderPath</HostFolder>
            <SandboxFolder>$SandboxFolderPath</SandboxFolder>
            <ReadOnly>false</ReadOnly>
        </MappedFolder>
    </MappedFolders>
    <LogonCommand>
        <Command>powershell -ExecutionPolicy Bypass -Command "Set-ExecutionPolicy Unrestricted -Force -Scope LocalMachine; Set-ExecutionPolicy Unrestricted -Force -Scope CurrentUser; Set-ExecutionPolicy Unrestricted -Force -Scope Process; Start-Process powershell -ArgumentList '$SandboxFolderPath\Scripts\Personal_DeviceSetup.ps1' -Wait -Verb RunAs; Start-Process powershell_ise -ArgumentList '$SandboxFolderPath\Scripts\Personal_ToolSetup.ps1' -Verb RunAs"</Command>
    </LogonCommand>
</Configuration>
"@
}

function Save-SandboxConfig {
    param (
        [string]$SandboxConfig,
        [string]$SandboxConfigPath
    )
    $configDir = Split-Path $SandboxConfigPath -Parent
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    }
    $SandboxConfig | Out-File -FilePath $SandboxConfigPath -Encoding UTF8 -Force
    Write-Host "[INFO] Sandbox configuration saved to: $SandboxConfigPath" -ForegroundColor Green
}

function Launch-WindowsSandbox {
    param (
        [string]$SandboxConfigPath
    )
    Write-Host "[INFO] Launching Windows Sandbox..." -ForegroundColor Cyan
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = "C:\Windows\System32\WindowsSandbox.exe"
    $startInfo.Arguments = "`"$SandboxConfigPath`""
    $startInfo.WorkingDirectory = Split-Path $startInfo.FileName -Parent
    $startInfo.UseShellExecute = $true
    $startInfo.Verb = "runas"
    
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $process.Start() | Out-Null
    Write-Host "[INFO] Windows Sandbox initialization completed successfully!" -ForegroundColor Green
}

if (-not (Test-AdminPrivileges)) {
    Elevate-AdminPrivileges
    return
}

try {
    Validate-SandboxFeature
    Validate-SandboxExecutable

    if($RefreshMappedFolder) {
        Remove-ExistingMappedFolder -HostFolderPath $HostFolderPath
        Create-MappedFolder -HostFolderPath $HostFolderPath
        Create-ScriptsFolder -HostFolderPath $HostFolderPath
        Copy-RequiredFiles -ScriptsFolder (Join-Path $HostFolderPath "Scripts")
    }
    $sandboxConfig = Create-SandboxConfig -SandboxConfigPath $SandboxConfigPath -HostFolderPath $HostFolderPath -SandboxFolderPath $SandboxFolderPath -EnableVGPU $EnableVGPU -EnableNetworking $EnableNetworking -MemoryInGB $MemoryInGB -vCPUs $vCPUs
    Save-SandboxConfig -SandboxConfig $sandboxConfig -SandboxConfigPath $SandboxConfigPath

    Launch-WindowsSandbox -SandboxConfigPath $SandboxConfigPath
}
catch {
    Write-Host "[ERROR] Failed to initialize Windows Sandbox: $_" -ForegroundColor Red
}
