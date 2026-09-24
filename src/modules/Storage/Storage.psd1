@{
    RootModule           = 'Storage.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = '8a2e5c7b-4f1d-4e9a-b3c6-7d0f2a9e5b1c'
    Author               = 'Monitor de Vencimentos'
    Description          = 'Acesso ao Table Storage via REST puro (sem Az/AzTable) do Monitor de Vencimentos.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport    = @(
        'ConvertTo-ValorFiltroOData'
        'New-CabecalhoTabela'
        'New-TabelaSeNaoExistir'
        'Set-Entidade'
        'Remove-Entidade'
        'Get-Entidades'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
}
