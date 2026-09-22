@{
    RootModule        = 'Vencimentos.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b6f1d3a2-6c1e-4f5b-9a57-3f0e8c2d7a41'
    Author            = 'Monitor de Vencimentos'
    Description       = 'Regras de vencimento, marcos de alerta e normalização de itens do Monitor de Vencimentos.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport = @(
        'Get-DataHojeBrasil'
        'Get-DiasRestantes'
        'Get-MarcoDevido'
        'Test-AlertaPendente'
        'ConvertTo-ItemNormalizado'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
}
