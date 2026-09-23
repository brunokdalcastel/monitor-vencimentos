@{
    RootModule           = 'Dominio.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'e7f4b1a2-6c9d-4f3e-8a1b-2d5c7e9f0a3b'
    Author               = 'Monitor de Vencimentos'
    Description          = 'Verificação de vencimento de domínio via RDAP do Monitor de Vencimentos.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport    = @(
        'ConvertTo-DominioNormalizado'
        'Get-VencimentoDominio'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
}
