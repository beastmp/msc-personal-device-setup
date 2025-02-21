@{
    RootModule = 'ApplicationManager.psm1'
    ModuleVersion = '1.0.0'
    GUID = '12345678-1234-1234-1234-123456789012'
    Author = 'Your Name'
    Description = 'Application Management Module'
    PowerShellVersion = '5.1'
    RequiredModules = @(
        'SystemOperations',
        'Monitoring',
        'StateManager'
    )
    FunctionsToExport = @('New-ApplicationManager')
    CmdletsToExport = @()
    VariablesToExport = '*'
    AliasesToExport = @()
}
