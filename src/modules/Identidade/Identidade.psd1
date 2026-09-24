@{
    RootModule           = 'Identidade.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '3b6d9f1a-7e2c-4a5b-9f0d-1c8e4a6b2d7f'
    Author               = 'Monitor de Vencimentos'
    Description          = 'Token de acesso via Managed Identity do Monitor de Vencimentos.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport    = @(
        'Get-TokenAcesso'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
}
