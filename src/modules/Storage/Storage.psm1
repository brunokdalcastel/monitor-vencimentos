#Requires -Version 5.1
# Módulo Storage — acesso ao Table Storage via REST puro (T05).
# Sem módulos Az/AzTable (ver ADR 0002). Autenticação: Managed Identity em prod,
# SharedKey (Azurite) local (ver ADR 0003), alternando só por TABELAS_MODO_AUTH.
# Compatível com PowerShell 7.4 (Functions) e Windows PowerShell 5.1.

Set-StrictMode -Version Latest

Import-Module "$PSScriptRoot/../Identidade/Identidade.psd1" -Force

$script:VersaoApiTabelas = '2020-12-06'

function Get-ConfiguracaoTabela {
    # Lê a configuração do Table Storage das variáveis de ambiente.
    # TABELAS_ENDPOINT: base da conta (ex.: 'https://<conta>.table.core.windows.net'
    #   em prod, 'http://127.0.0.1:10002/devstoreaccount1' contra o Azurite local).
    # TABELAS_MODO_AUTH: 'ManagedIdentity' (prod) ou 'SharedKey' (só local, Azurite).
    # TABELAS_CONTA/TABELAS_CHAVE: só usados (e obrigatórios) no modo SharedKey.
    $endpoint = $env:TABELAS_ENDPOINT
    $modoAuth = $env:TABELAS_MODO_AUTH

    if (-not $endpoint) {
        throw 'TABELAS_ENDPOINT não configurado.'
    }
    if ($modoAuth -ne 'ManagedIdentity' -and $modoAuth -ne 'SharedKey') {
        throw "TABELAS_MODO_AUTH inválido: '$modoAuth'. Use 'ManagedIdentity' ou 'SharedKey'."
    }
    if ($modoAuth -eq 'SharedKey' -and (-not $env:TABELAS_CONTA -or -not $env:TABELAS_CHAVE)) {
        throw 'TABELAS_CONTA e TABELAS_CHAVE são obrigatórios quando TABELAS_MODO_AUTH=SharedKey (uso local contra Azurite).'
    }

    return [pscustomobject] [ordered] @{
        Endpoint = $endpoint.TrimEnd('/')
        ModoAuth = $modoAuth
        Conta    = $env:TABELAS_CONTA
    }
}

function ConvertTo-ValorFiltroOData {
    <#
    .SYNOPSIS
        Escapa um valor para uso seguro dentro de um filtro ou chave OData.
    .DESCRIPTION
        Único caractere especial em literais string OData é a aspa simples,
        escapada dobrando-a (regra padrão OData/Table Storage).
    .OUTPUTS
        string
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Valor
    )

    return $Valor -replace "'", "''"
}

function Get-CodigoStatusHttp {
    # Extrai o código HTTP de uma exceção do Invoke-WebRequest: Response.StatusCode
    # (WebException no 5.1, HttpResponseException no 7.x) e, na falta dele
    # (ex.: exceções simuladas em teste), a mensagem da exceção.
    param(
        [System.Exception] $Excecao
    )

    if (-not $Excecao) {
        return $null
    }

    if ($Excecao.PSObject.Properties.Match('Response').Count -gt 0 -and $Excecao.Response) {
        $resposta = $Excecao.Response
        if ($resposta.PSObject.Properties.Match('StatusCode').Count -gt 0 -and $resposta.StatusCode) {
            return [int] $resposta.StatusCode
        }
    }

    if ($Excecao.Message -match '\b(\d{3})\b') {
        return [int] $Matches[1]
    }

    return $null
}

function Get-CabecalhoResposta {
    # Lê um cabeçalho de uma resposta do Invoke-WebRequest, cross-versão: no 7.x
    # cada valor vem como string[]; no 5.1, como string única.
    param(
        $Resposta,

        [Parameter(Mandatory)]
        [string] $Nome
    )

    if (-not $Resposta -or -not $Resposta.Headers) {
        return $null
    }

    $valor = $Resposta.Headers[$Nome]
    if ($null -eq $valor) {
        return $null
    }
    if ($valor -is [array]) {
        if ($valor.Count -eq 0) { return $null }
        return $valor[0]
    }
    return $valor
}

function New-CabecalhoTabela {
    <#
    .SYNOPSIS
        Monta os cabeçalhos HTTP (incluindo autenticação) para uma chamada ao Table Storage.
    .DESCRIPTION
        Modo 'ManagedIdentity': Authorization Bearer com token do Get-TokenAcesso
        (módulo Identidade). Modo 'SharedKey': assinatura SharedKeyLite contra o
        Azurite local. Nas URLs path-style do Azurite (conta no caminho, não no
        host) o recurso canonicalizado repete a conta — é assim que o Azurite
        valida a assinatura; verificado empiricamente contra o Azurite 3.37 (ver
        Pendências da T05 no PLANO.md).
    .PARAMETER CaminhoRecurso
        Caminho do recurso (ex.: 'Tables', 'Itens()', "Itens(PartitionKey='x',RowKey='y')"),
        sem query string — usado na assinatura SharedKeyLite.
    .PARAMETER ComCorpo
        Inclui o cabeçalho Content-Type para requisições com corpo JSON.
    .OUTPUTS
        hashtable de cabeçalhos HTTP.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Não muda estado: só monta cabeçalhos HTTP. Nome definido no PLANO.md (T05).')]
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $CaminhoRecurso,

        [switch] $ComCorpo
    )

    $config = Get-ConfiguracaoTabela
    $data = [datetime]::UtcNow.ToString('r', [System.Globalization.CultureInfo]::InvariantCulture)

    $cabecalhos = @{
        'x-ms-date'    = $data
        'x-ms-version' = $script:VersaoApiTabelas
        'Accept'       = 'application/json;odata=nometadata'
    }
    if ($ComCorpo) {
        $cabecalhos['Content-Type'] = 'application/json'
    }

    if ($config.ModoAuth -eq 'ManagedIdentity') {
        $token = Get-TokenAcesso -Recurso 'https://storage.azure.com'
        $cabecalhos['Authorization'] = "Bearer $token"
    }
    else {
        $stringToSign = "$data`n/$($config.Conta)/$($config.Conta)/$CaminhoRecurso"
        $chaveBytes = [Convert]::FromBase64String($env:TABELAS_CHAVE)
        $hmac = New-Object System.Security.Cryptography.HMACSHA256
        $hmac.Key = $chaveBytes
        try {
            $assinaturaBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($stringToSign))
        }
        finally {
            $hmac.Dispose()
        }
        $cabecalhos['Authorization'] = "SharedKeyLite $($config.Conta):$([Convert]::ToBase64String($assinaturaBytes))"
    }

    return $cabecalhos
}

function Invoke-RequisicaoTabela {
    # Chamada HTTP de baixo nível compartilhada pelas funções públicas do módulo.
    param(
        [Parameter(Mandatory)]
        [string] $Metodo,

        [Parameter(Mandatory)]
        [string] $CaminhoRecurso,

        [string] $QueryString = '',

        [object] $Corpo,

        [hashtable] $CabecalhosExtras
    )

    $config = Get-ConfiguracaoTabela
    $comCorpo = $null -ne $Corpo
    $cabecalhos = New-CabecalhoTabela -CaminhoRecurso $CaminhoRecurso -ComCorpo:$comCorpo
    if ($CabecalhosExtras) {
        foreach ($chave in $CabecalhosExtras.Keys) {
            $cabecalhos[$chave] = $CabecalhosExtras[$chave]
        }
    }

    # -UseBasicParsing evita a dependência do engine do IE que o Invoke-WebRequest usa por
    # padrão no Windows PowerShell 5.1 (sem isso, POST/PUT/DELETE falham com
    # "Object reference not set to an instance of an object" ou travam se o IE não
    # tiver passado pela configuração inicial).
    $parametros = @{
        Uri             = "$($config.Endpoint)/$CaminhoRecurso$QueryString"
        Method          = $Metodo
        Headers         = $cabecalhos
        ErrorAction     = 'Stop'
        UseBasicParsing = $true
    }
    if ($comCorpo) {
        $parametros['Body'] = ($Corpo | ConvertTo-Json -Depth 10)
        $parametros['ContentType'] = 'application/json'
    }

    return Invoke-WebRequest @parametros
}

function New-TabelaSeNaoExistir {
    <#
    .SYNOPSIS
        Cria a tabela se ela ainda não existir. Idempotente.
    .PARAMETER Tabela
        Nome da tabela.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $Tabela
    )

    if (-not $PSCmdlet.ShouldProcess($Tabela, 'Criar tabela (se não existir)')) {
        return
    }

    try {
        Invoke-RequisicaoTabela -Metodo 'POST' -CaminhoRecurso 'Tables' -Corpo ([ordered] @{ TableName = $Tabela }) | Out-Null
    }
    catch {
        if ((Get-CodigoStatusHttp -Excecao $_.Exception) -eq 409) {
            return
        }
        throw
    }
}

function Set-Entidade {
    <#
    .SYNOPSIS
        Upsert (InsertOrReplace) de uma entidade na tabela.
    .PARAMETER Tabela
        Nome da tabela.
    .PARAMETER Entidade
        Hashtable ou pscustomobject com, no mínimo, PartitionKey e RowKey.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $Tabela,

        [Parameter(Mandatory)]
        [object] $Entidade
    )

    $entidadeObj = [pscustomobject] $Entidade
    if (-not $entidadeObj.PartitionKey -or -not $entidadeObj.RowKey) {
        throw 'Entidade precisa de PartitionKey e RowKey.'
    }

    $chavePk = ConvertTo-ValorFiltroOData -Valor $entidadeObj.PartitionKey
    $chaveRk = ConvertTo-ValorFiltroOData -Valor $entidadeObj.RowKey
    $caminho = "$Tabela(PartitionKey='$chavePk',RowKey='$chaveRk')"

    if (-not $PSCmdlet.ShouldProcess("$Tabela/$caminho", 'Upsert (InsertOrReplace) de entidade')) {
        return
    }

    Invoke-RequisicaoTabela -Metodo 'PUT' -CaminhoRecurso $caminho -Corpo $entidadeObj | Out-Null
}

function Remove-Entidade {
    <#
    .SYNOPSIS
        Remove uma entidade da tabela pela chave.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string] $Tabela,

        [Parameter(Mandatory)]
        [string] $PartitionKey,

        [Parameter(Mandatory)]
        [string] $RowKey
    )

    $chavePk = ConvertTo-ValorFiltroOData -Valor $PartitionKey
    $chaveRk = ConvertTo-ValorFiltroOData -Valor $RowKey
    $caminho = "$Tabela(PartitionKey='$chavePk',RowKey='$chaveRk')"

    if (-not $PSCmdlet.ShouldProcess("$Tabela/$caminho", 'Remover entidade')) {
        return
    }

    Invoke-RequisicaoTabela -Metodo 'DELETE' -CaminhoRecurso $caminho -CabecalhosExtras @{ 'If-Match' = '*' } | Out-Null
}

function Get-Entidades {
    <#
    .SYNOPSIS
        Consulta entidades de uma tabela, paginando automaticamente por x-ms-continuation-*.
    .PARAMETER Tabela
        Nome da tabela.
    .PARAMETER Filtro
        Expressão OData de filtro (ex.: "PartitionKey eq 'x'"). Use
        ConvertTo-ValorFiltroOData para escapar valores interpolados.
    .PARAMETER Select
        Lista de propriedades separadas por vírgula (`$select`), opcional.
    .OUTPUTS
        object[] — todas as entidades encontradas, já com todas as páginas resolvidas.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nome definido no PLANO.md (T05): devolve várias entidades.')]
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [string] $Tabela,

        [string] $Filtro,

        [string] $Select
    )

    $entidades = New-Object System.Collections.Generic.List[object]
    $proximaParticao = $null
    $proximaLinha = $null

    do {
        $parametrosQuery = New-Object System.Collections.Generic.List[string]
        if ($Filtro) { $parametrosQuery.Add("`$filter=$([uri]::EscapeDataString($Filtro))") }
        if ($Select) { $parametrosQuery.Add("`$select=$([uri]::EscapeDataString($Select))") }
        if ($proximaParticao) { $parametrosQuery.Add("NextPartitionKey=$([uri]::EscapeDataString($proximaParticao))") }
        if ($proximaLinha) { $parametrosQuery.Add("NextRowKey=$([uri]::EscapeDataString($proximaLinha))") }

        $queryString = ''
        if ($parametrosQuery.Count -gt 0) {
            $queryString = '?' + ($parametrosQuery -join '&')
        }

        $resposta = Invoke-RequisicaoTabela -Metodo 'GET' -CaminhoRecurso "$Tabela()" -QueryString $queryString
        $corpo = $resposta.Content | ConvertFrom-Json
        foreach ($item in $corpo.value) {
            $entidades.Add($item)
        }

        $proximaParticao = Get-CabecalhoResposta -Resposta $resposta -Nome 'x-ms-continuation-NextPartitionKey'
        $proximaLinha = Get-CabecalhoResposta -Resposta $resposta -Nome 'x-ms-continuation-NextRowKey'
    } while ($proximaParticao)

    # A vírgula unária evita que o PowerShell "desembrulhe" um resultado de 1 item
    # (ou remova por completo um resultado de 0 itens) ao percorrer o pipeline do
    # return — sem ela, quem chama e faz .Count ou [0] quebra no Windows PowerShell
    # 5.1 quando há exatamente 1 entidade (no 7.x o efeito fica mascarado porque
    # todo objeto passou a responder .Count desde a 7.0).
    return , $entidades.ToArray()
}

Export-ModuleMember -Function @(
    'ConvertTo-ValorFiltroOData'
    'New-CabecalhoTabela'
    'New-TabelaSeNaoExistir'
    'Set-Entidade'
    'Remove-Entidade'
    'Get-Entidades'
)
