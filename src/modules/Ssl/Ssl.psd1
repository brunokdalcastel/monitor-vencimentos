@{
    RootModule           = 'Ssl.psm1'
    ModuleVersion        = '0.1.0'
    GUID                 = 'a4d2c8e1-9b3f-4a6d-8e2c-1f7b5d0a9c34'
    Author               = 'Monitor de Vencimentos'
    Description          = 'Verificação de certificado SSL/TLS (conexão direta na porta) do Monitor de Vencimentos.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')

    FunctionsToExport    = @(
        'ConvertTo-EnderecoSsl'
        'Get-CertificadoSsl'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
}
