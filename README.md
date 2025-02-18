# Personal Windows Automation

A collection of PowerShell scripts and configuration files for automating Windows setup and maintenance.

## Features

- Windows migration guide and download links
- Device preparation and system requirement checks
- Automated software installation using Winget
- Application data backup functionality
- Silent installation configuration

## Directory Structure
\\\
/docs         - Documentation
/src/scripts  - PowerShell scripts
/src/config   - Configuration files
/src/data     - Data files and templates
\\\

## Getting Started

1. Clone this repository
2. Review the configuration in \/src/config/softwarelist.json\
3. Run the desired script from \/src/scripts\

## Scripts

### Prepare-Device.ps1
Checks system requirements and prepares device for Windows installation:
- Verifies TPM, Secure Boot, CPU, RAM, and Storage requirements
- Backs up application data

### Install-Tools.ps1
Automated software installation script:
- Uses Winget for package management
- Supports custom installation paths
- Handles pre/post install actions

### Test-ToolSetup.ps1
Testing utilities for software installation:
- Validates installation paths
- Tests machine scope installations
- Verifies symbolic links

## Configuration

### softwarelist.json
Contains software installation configuration:
- Installation paths
- Download URLs
- Silent install arguments
- Version requirements

### git-install-options.txt
Silent installation options for Git:
- Custom installation path
- Component selection
- Configuration settings
