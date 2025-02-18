$Script:InstallLocation = "C:\Testing\Microsoft\AIShell"
$Script:PackageURL = "https://github.com/PowerShell/AIShell/releases/download/v1.0.0-preview.1/AIShell-1.0.0-preview.1-win-X64.zip"

function Install-AIShellApp {
    [CmdletBinding()]
    param()

    $destination = $Script:InstallLocation
    $packageUrl = $Script:PackageURL

    New-Item -Path $destination -ItemType Directory -Force | Out-Null

    $fileName = [System.IO.Path]::GetFileName($packageUrl)
    Join-Path $StagingDirectory $fileName

    # Download AIShell package.
    Write-Host "Downloading AI Shell package '$fileName' ..."
    Invoke-WebRequest -Uri $packageUrl -OutFile $tempPath -ErrorAction Stop

        # Extract AIShell package.
        Write-Host "Extracting AI Shell to '$destination' ..."
        Unblock-File -Path $tempPath #Interesting: Used to unblock for "unsafe" downloads from the internet
        Expand-Archive -Path $tempPath -DestinationPath $destination -Force -ErrorAction Stop

        # Set the process-scope and user-scope Path env variables to include AIShell.
        $envPath = $env:Path
        if (-not $envPath.Contains($destination)) {
            Write-Host "Adding AI Shell app to the Path environment variable ..."
            $env:Path = "${destination};${envPath}"
            $userPath = [Environment]::GetEnvironmentVariable('Path', [EnvironmentVariableTarget]::User)
            $newUserPath = if($userPath.EndsWith(';')){"${userPath}${destination}"}else{"${userPath};${destination}"}
            [Environment]::SetEnvironmentVariable('Path', $newUserPath, [EnvironmentVariableTarget]::User)
        }
}

function Install-AIShellModule {
    Write-Host "Installing the PowerShell module 'AIShell' ..."
    Install-PSResource -Name AIShell -Repository PSGallery -Prerelease -TrustRepository -ErrorAction Stop -WarningAction SilentlyContinue
}

Start-AIShell