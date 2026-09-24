@{
    RootModule           = 'Email.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'f1a4d7c2-8b5e-4c9a-a1f3-6e2b9d4c7a08'
    Author               = 'Monitor de Vencimentos'
    Description          = 'Envio de alertas por e-mail via Azure Communication Services do Monitor de Vencimentos.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport    = @(
        'ConvertTo-TextoHtmlSeguro'
        'New-EmailAlerta'
        'New-EmailResumoAdmin'
        'Send-EmailAcs'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
}
