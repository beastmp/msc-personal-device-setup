MSI
https://download.msi.com/bos_exe/mb/7881vA82.zip

https://download.msi.com/dvr_exe/intel_chipset_w10.zip
https://download.msi.com/dvr_exe/intel_bt_10.zip
https://download.msi.com/dvr_exe/mb/realtek_hd_audio.zip
https://download.msi.com/dvr_exe/Intel_Network_Drivers.zip
https://download.msi.com/dvr_exe/intel_rapid_storage_w10.zip
https://download.msi.com/dvr_exe/intel_me_9_w10.zip
https://download.msi.com/dvr_exe/intel_tbmt.zip
https://download.msi.com/dvr_exe/mb/asmedia_usb31_win7.zip

https://download.msi.com/uti_exe/mb/CPU_Z.zip
https://download.msi.com/uti_exe/mb/LiveUpdate.zip
https://download.msi.com/uti_exe/mb/command_center.zip
https://download.msi.com/uti_exe/mb/SuperCharger_mb_1.3.0.29.zip
https://download.msi.com/uti_exe/FastBoot_mb_1.0.1.15.zip
https://download.msi.com/uti_exe/extreme_tuning_9_w10.zip
https://download.msi.com/uti_exe/directoc_win78.zip
https://download.msi.com/uti_exe/eco_center.zip

Samsung_Magician
https://download.semiconductor.samsung.com/resources/software-resources/Samsung_Magician_Installer_Official_8.2.0.880.exe
Seagate_Dashboard (Replaced By Toolkit)
https://www.seagate.com/content/dam/seagate/migrated-assets/www-content/support-content/software/toolkit/_Shared/master/SeagateToolkit.exe
https://www.seagate.com/content/dam/seagate/migrated-assets/www-content/support-content/downloads/seatools/_shared/downloads/SeaToolsWindowsInstaller.exe
https://www.seagate.com/content/dam/seagate/migrated-assets/www-content/support-content/downloads/discwizard/_shared/downloads/SeagateDiscWizard.zip
Seagate drive paragon driver
https://www.seagate.com/content/dam/seagate/migrated-assets/www-content/support-content/external-products/backup-plus/_shared/downloads/HFS4WIN.msi

Winget
Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe

Winget in Windows Sandbox
$progressPreference = 'silentlyContinue'
Write-Host "Installing WinGet PowerShell module from PSGallery..."
Install-PackageProvider -Name NuGet -Force | Out-Null
Install-Module -Name Microsoft.WinGet.Client -Force -Repository PSGallery | Out-Null
Write-Host "Using Repair-WinGetPackageManager cmdlet to bootstrap WinGet..."
Repair-WinGetPackageManager
Write-Host "Done."

winget settings --enable LocalManifestFiles

https://learn.microsoft.com/en-us/windows/package-manager/winget/
https://powershellisfun.com/2024/11/28/using-the-powershell-winget-module/
https://winaero.com/install-a-winget-app-with-custom-arguments-and-command-line-switches/
https://answers.microsoft.com/en-us/msoffice/forum/all/move-a-installed-application-to-a-different-drive/170d2b11-c879-4b9c-8142-dfcbbc8d2e03
https://www.howtogeek.com/16226/complete-guide-to-symbolic-links-symlinks-on-windows-or-linux/
https://www.advancedinstaller.com/silent-install-exe-msi-applications.html

CommandLine Switches:
PowerShell: https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows?view=powershell-7.5
Visual Studio: https://learn.microsoft.com/en-us/visualstudio/install/use-command-line-parameters-to-install-visual-studio?view=vs-2022
Git: https://github.com/git-for-windows/git/wiki/Silent-or-Unattended-Installation
Power Automate Desktop: https://learn.microsoft.com/en-us/power-automate/desktop-flows/install-silently
MySQL: https://dev.mysql.com/doc/refman/9.1/en/windows-installation.html
https://dev.mysql.com/doc/refman/8.0/en/mysql-installer.html
https://dev.mysql.com/doc/refman/8.0/en/MySQLInstallerConsole.html
MySQL Configurator: https://dev.mysql.com/doc/refman/9.1/en/mysql-configurator-cli.html

C:\Temp\Scripts\Personal_ToolSetup.ps1 -Verbose -Debug -TestingMode -Action Install -ApplicationName 

TODO

Folder Locations
Alexa:
C:\Users\WDAGUtilityAccount\AppData\Local\Packages\57540AMZNMobileLLC.AmazonAlexa_22t9g3sebte08
"C:\Program Files\WindowsApps\57540AMZNMobileLLC.AmazonAlexa_3.25.1177.0_neutral_~_22t9g3sebte08"
"C:\Program Files\WindowsApps\57540AMZNMobileLLC.AmazonAlexa_3.25.1177.0_neutral_split.scale-100_22t9g3sebte08"
"C:\Program Files\WindowsApps\57540AMZNMobileLLC.AmazonAlexa_3.25.1177.0_x64__22t9g3sebte08"

Astro:
C:\Users\WDAGUtilityAccount\AppData\Local\Packages\AstroGaming.AstroCommandCenter_9cg1kgznx2mv2
"C:\Program Files\WindowsApps\AstroGaming.AstroCommandCenter_1.1.55.0_neutral_~_9cg1kgznx2mv2"
"C:\Program Files\WindowsApps\AstroGaming.AstroCommandCenter_1.1.55.0_neutral_split.scale-100_9cg1kgznx2mv2"
"C:\Program Files\WindowsApps\AstroGaming.AstroCommandCenter_1.1.55.0_x64__9cg1kgznx2mv2"

BattleNet:
"C:\Users\WDAGUtilityAccount\AppData\Local\Battle.net"
"C:\Users\WDAGUtilityAccount\AppData\Roaming\Battle.net"
"C:\Users\WDAGUtilityAccount\AppData\Local\Blizzard Entertainment"
C:\ProgramData\Battle.net
C:\ProgramData\Battle.net_components

CapCut:
"C:\Users\WDAGUtilityAccount\AppData\Local\CapCut"

Cookn:
"C:\Users\WDAGUtilityAccount\AppData\Local\DVO"

Cursor:
"C:\Users\WDAGUtilityAccount\AppData\Local\cursor-updater"

Discord:
"C:\Users\WDAGUtilityAccount\AppData\Local\Discord"

Docker:
"C:\Users\WDAGUtilityAccount\AppData\Roaming\Docker"
"C:\ProgramData\DockerDesktop"

EA:
C:\ProgramData\EA Desktop
"C:\Users\WDAGUtilityAccount\AppData\Local\EADesktop"
"C:\Users\WDAGUtilityAccount\AppData\Local\Electronic Arts"
"C:\Users\WDAGUtilityAccount\AppData\Local\Origin"

Google Chrome:
C:\Program Files\Google\Chrome
"C:\Program Files (x86)\Google"

Google Drive:
C:\Program Files\Google\Drive File Stream

MySQL:
C:\ProgramData\MySQL
"C:\Program Files (x86)\MySQL"

Notepad++:
"C:\Users\WDAGUtilityAccount\AppData\Roaming\Notepad++"

NVIDIA GEForceNow:
"C:\Users\WDAGUtilityAccount\AppData\Local\NVIDIA Corporation\GeForceNOW"

Playstation Remote Play:
"C:\Program Files (x86)\Sony\PS Remote Play"

Plex Desktop:
"C:\Users\WDAGUtilityAccount\AppData\Local\Plex"

PlexAmp:
"C:\Users\WDAGUtilityAccount\AppData\Local\plexamp-updater"
"C:\Users\WDAGUtilityAccount\AppData\Local\Programs\Plexamp"

Plex Media Server:
"C:\Users\WDAGUtilityAccount\AppData\Local\Plex Media Server"

Power Automate Desktop:
"C:\Users\WDAGUtilityAccount\AppData\Local\Microsoft\Power Automate Desktop"

Power Toys:
"C:\Program Files\PowerToys"

Samsung Flow:
"C:\ProgramData\Packages\SAMSUNGELECTRONICSCoLtd.SamsungFlux_wyx1vj98g3asy"
"C:\Users\WDAGUtilityAccount\AppData\Local\Packages\SAMSUNGELECTRONICSCoLtd.SamsungFlux_wyx1vj98g3asy"
"C:\Program Files\WindowsApps\SAMSUNGELECTRONICSCoLtd.SamsungFlux_4.9.1403.0_neutral_~_wyx1vj98g3asy"
"C:\Program Files\WindowsApps\SAMSUNGELECTRONICSCoLtd.SamsungFlux_4.9.1403.0_neutral_split.scale-100_wyx1vj98g3asy"
"C:\Program Files\WindowsApps\SAMSUNGELECTRONICSCoLtd.SamsungFlux_4.9.1403.0_x64__wyx1vj98g3asy"

Samsung Toolkit:
"C:\Users\WDAGUtilityAccount\AppData\Roaming\Toolkit"

Steam:
"C:\Program Files (x86)\Common Files\Steam"

Visual Studio:
C:\ProgramData\Microsoft\VisualStudio
"C:\Users\WDAGUtilityAccount\AppData\Local\Microsoft\VisualStudio"
"C:\Users\WDAGUtilityAccount\AppData\Roaming\Visual Studio Setup"
"C:\Program Files (x86)\Microsoft Visual Studio"

C:\Program Files (x86)\MySQL\MySQL Installer for Windows\MySQLInstallerConsole.exe" community install server;5.7.22;x64 workbench;6.3.10;x64 -silent
msiexec /q /log install.txt /i mysql-advanced-5.1.32-win32.msi datadir=”c:\installs\myapp” installdir=”c:\installs\myapp”
MySQLInstanceConfig.exe -i -q “-lC:\mysql_install_log.txt” “-nMySQL Server 5.1.234” -pC:\installs\myapp”   -v5.1.234  “tc:\installs\myapp\my-small.ini” “-cC:\mytest.ini ServerType=DEVELOPMENT DatabaseType=MIXED ConnectionUsage=DSS Port=3311 ServiceName=MySQLCust RootPassword=1234


https://download.msi.com/bos_exe/mb/7881vA82.zip

https://github.com/pbatard/rufus/releases/download/v4.6/rufus-4.6.exe

Specific App Backup

Cursor Script Creation:
I would like to create an automated software installer script that will perform the following:
- It should allow for the configuration of the software that will be installed based on a JSON file with the following structure:
    - Name: the name of the software. This can contain underscores which will be used to denote subdirectories in the install directory. (Required)
    - Version: the version of the software. This can be "latest" or a specific version number. (Required)
    - WingetID: the ID of the software in the Winget repository. This is only required if the software is available through Winget.
    - ModuleID: the ID of the software in the PowerShell Gallery. This is only required if the software is available through the PowerShell Gallery.
    - Download: a boolean value that determines if the software should be downloaded. (Required)
    - Install: a boolean value that determines if the software should be installed. (Required)
    - DownloadURL: the URL of the software download. This is only required if the software is not available through Winget.
    - InstallerArguments: the arguments to pass to the installer. This is only required if the software is not available through Winget.
    - WingetInstallerArguments: the arguments to pass to the Winget installer. This is only required if the software is available through Winget.
    - UninstallerArguments: the arguments to pass to the uninstaller. This is only required if the software is available through Winget.
    - WingetUninstallerArguments: the arguments to pass to the Winget uninstaller. This is only required if the software is available through Winget.
- It should allow for the configuration of of the following parameters:
    - Binaries directory: defaults to C:\Temp\Binaries
    - Scripts directory: defaults to C:\Temp\Scripts
    - Staging directory: defaults to C:\Temp\Staging
    - Install directory: defaults to C:\Temp\Apps
    - Post install directory: defaults to C:\Temp\Installed
    - Log directory: defaults to C:\Temp\Logs
    - Software list file name: defaults to personal_softwarelist.json
    - Action (Install or Uninstall)
    - Application name (optional, for single application)
    - Application version (optional, for single application)
- It should proceed through the following steps:
    - Main Pre-Step
        - Creates the Log directory if it does not exist
        - Creates and starts a transcript in the log directory with the following naming convention: Transcript-ToolSetup-Action-HostName-Version-DateTime.txt
        - Sets the Debug Preference to Continue
        - Sets the current execution location to the scripts directory
        - Gets the software list from the software list file
        - Checks for Winget and the WinGet PowerShell module and installs them if they are not found
    - If action is Install:
        - Main Install Pre-Step
            - Creates the Binaries, Staging, and PostInstall directories if they do not exist
        - For each application in the software list:
            - If the ApplicationName and ApplicationVersion are not provided, or if the application name and version do not match the current application, skip to the next application.
            - Set the InstallPath property of the application
                - if the application name contains underscores, use the first underscore to denote the subdirectory in the install directory
                - otherwise, use the application name as the subdirectory in the install directory
            - Set the BinaryPath property of the application to the binaries directory + the application name + _ + the application version + the file extension
            - Set the StagedPath property of the application to the staging directory + the application name + _ + the application version + the file extension
            - Set the PostInstallPath property of the application to the post install directory + the application name + _ + the application version + the file extension
            - If the InstallerArguments or WingetInstallerArguments properties are set, replace any of the following placeholders with the actual values:
                - $Name
                - $Version
                - $InstallPath
                - $BinaryPath
                - $StagedPath
                - $PostInstallPath
                - $BinariesDirectory
                - $StagingDirectory
                - $InstallDirectory
                - $PostInstallDirectory
            - Download Pre-Step
                -Specific to the application
            - Download the application
                - If the Download property is true, download the application with the following steps:
                    -If the WingetID property is set:
                        - Create a directory in the binaries directory with the following naming convention: the application name + _ + the application version
                        - Download the application using Winget with the following arguments:
                            - --id $WingetID
                            - --download-directory "`"the binaries directory + the application name + _ + the application version`""
                            - --accept-source-agreements
                            - --accept-package-agreements
                            - If the Version property is not "latest", add the --version argument with the value of the Version property
                        - If the application files are downloaded to the download directory successfully:
                            - move them to the binaries directory with the following naming convention:
                                - if it is a file: the application name + _ + the application version + the file extension
                                - if it is a directory: the application name + _ + the application version + the directory name
                            - remove the application binary directory
                    - If the ModuleID property is set:
                        - Download the Module from the PowerShell Gallery with the following arguments:
                            - -Name: the ModuleID property
                            - -Path: "`"the binaries directory + the application name + _ + the application version`""
                            - If the Version property is not "latest", add the -RequiredVersion argument with the value of the Version property
                            - -AcceptLicense
                            - -Force
                    - If the DownloadURL property is set:
                        - Download the application using the Invoke-WebRequest cmdlet with the following arguments:
                            - -Uri: the DownloadURL property
                            - -OutFile: the binaries directory + the application name + _ + the application version + the file extension
            - Download Post-Step
                -Specific to the application
            - If the application is downloaded successfully, copy the application to the staging directory with the following naming convention: the application name + _ + the application version + the file extension
            - Install Pre-Step
                -Specific to the application
            - Install the application
                -If the Install property is true, install the application with the following steps:
                    -If the WingetID property is set:   
                        - Install the application using Winget with the following arguments:
                            - --id $WingetID
                            - --location "`"$InstallPath`""
                            - --accept-source-agreements
                            - --accept-package-agreements
                            - --silent
                            - --force
                            - If the Version property is not "latest", add the --version argument with the value of the Version property
                            - If the WingetInstallerArguments property is set, add the arguments to the Winget command
                    - If the ModuleID property is set:
                        - Install the module using the Install-Module cmdlet with the following arguments:
                            - -Name: the ModuleID property
                            - -AcceptLicense
                            - -Force
                            - If the Version property is not "latest", add the -RequiredVersion argument with the value of the Version property
                            - -Scope: AllUsers
                            - -Confirm: False
                    - If the WingetID property is not set:
                        - Install the application using the based on its file extension:
                            - .zip: Extract the application zip file from the staging directory to the install directory
                            - .msi: Use msiexec to run the installer from the staging directory with the following arguments:
                                - passive
                                - norestart
                                - any custom arguments defined in the application's InstallerArguments property
                            - .exe: run the installer from the staging directory with any custom arguments defined in the application's InstallerArguments property
            - Install Post-Step
                -Specific to the application
            - If the application is installed successfully, move the application from the staging directory to the post install directory with the following naming convention: the application name + _ + the application version + the file extension
        - Main Install Post-Step
    - If action is Uninstall:
        - Main Uninstall Pre-Step
        - For each application in the software list:
            - Uninstall the application
        - Main Uninstall Post-Step
- It should have a centralized logging function
    - It should log the following levels:
        - INFO: General information about the script and its progress
        - SUCCESS: Successful completion of a step
        - ERROR: An error occurred during a step
        - WARNING: A warning occurred during a step
        - DEBUG: Debug information for troubleshooting
        - VERBOSE: Verbose information for troubleshooting
        - PROGRESS: Time elapsed for a step
    - It should only show debug and verbose messages if the Debug and Verbose parameters are set to true
    - It should associate the log level with a color:
        - INFO: White
        - SUCCESS: Green
        - ERROR: Red
        - WARNING: Yellow
        - DEBUG: Cyan
        - VERBOSE: DarkYellow
        - PROGRESS: Magenta
    - Will write to the console with the following format:
        - [Timestamp] [LogLevel.PadRight(7)] [Message] -ForegroundColor $color
        - Timestamp: The current date and time in the format of yyyyMMdd_HHmmss
        - LogLevel: The log level formatted to be left-aligned within a space of 7 characters
        - Message: The message to log
        - ForegroundColor: The color to use for the message
- It should wrap all commands in a try/catch block and will send the code and error message to the logging function at the ERROR level if an error occurs
- It should send all commands to the logging function at the DEBUG level
- It should log a beginning and end message at the VERBOSE level for all non-main steps and functions
- It should log a beginning and end message at the INFO level for all main steps
- It should log a message at the SUCCESS level for all main steps that are successful
- It should log the time elapsed at the PROGRESS level for all steps
