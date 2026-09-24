@{
    RootModule           = 'Orquestrador.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'c6a3e9f4-2d7b-4e18-9a5c-3f8b1d6e4c90'
    Author               = 'Monitor de Vencimentos'
    Description          = 'Orquestrador da verificação diária de vencimentos do Monitor de Vencimentos.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport    = @(
        'Invoke-VerificacaoDiaria'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
}
