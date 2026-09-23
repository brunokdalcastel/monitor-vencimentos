#Requires -Version 5.1
# Módulo Dominio — verificação de vencimento de domínio via RDAP (T04).
# Compatível com PowerShell 7.4 (Functions) e Windows PowerShell 5.1.

Set-StrictMode -Version Latest

function ConvertTo-DominioNormalizado {
    <#
    .SYNOPSIS
        Normaliza um domínio cadastrado (Alvo) para uso na consulta RDAP.
    .DESCRIPTION
        Remove esquema (http://, https://), prefixo 'www.', caminho/query/fragmento
        e converte para minúsculas.
    .PARAMETER Dominio
        Texto livre cadastrado no item (coluna Alvo da tabela Itens, Tipo=Dominio).
    .OUTPUTS
        string — domínio normalizado (ex.: 'exemplo.com.br').
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Dominio
    )

    $texto = $Dominio.Trim()
    if ($texto -eq '') {
        throw 'Domínio é obrigatório.'
    }

    $texto = $texto -replace '^[a-zA-Z][a-zA-Z0-9+.-]*://', ''
    $texto = ($texto -split '[/?#]')[0]
    $texto = $texto.Trim().ToLowerInvariant()
    $texto = $texto -replace '^www\.', ''

    if ($texto -eq '') {
        throw "Domínio inválido: '$Dominio'."
    }

    return $texto
}

function Get-CodigoStatusHttp {
    # Extrai o código HTTP de uma exceção do Invoke-RestMethod, tentando primeiro
    # Exception.Response.StatusCode (WebException no 5.1, HttpResponseException no 7.x)
    # e, na falta dele (ex.: exceções simuladas em teste), a mensagem da exceção.
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

    if ($Excecao.Message -match '\b(404|429)\b') {
        return [int] $Matches[1]
    }

    return $null
}

function Get-VencimentoDominio {
    <#
    .SYNOPSIS
        Consulta o RDAP e devolve a data de expiração de um domínio.
    .DESCRIPTION
        Domínios '.br' são consultados direto em rdap.registro.br; os demais via
        bootstrap IANA (rdap.org), que redireciona para o servidor RDAP correto do TLD.
        Em caso de 404 (domínio não encontrado), devolve Status='NaoEncontrado' sem erro.
        Em caso de 429 (rate limit), faz uma nova tentativa após espera. Qualquer outra
        falha (timeout, serviço fora, resposta sem evento de expiração) é reportada em
        Erro, sem lançar exceção — cabe ao chamador decidir o que fazer (ver regra de
        falha de verificação no PLANO.md).
    .PARAMETER Dominio
        Domínio cadastrado (Alvo do item). Aceita URL completa, com ou sem 'www.'.
    .PARAMETER TimeoutSec
        Timeout da requisição RDAP em segundos. Padrão 10.
    .PARAMETER EsperaRetentativaMs
        Espera antes da nova tentativa em caso de 429. Padrão 2000ms.
    .OUTPUTS
        pscustomobject com DataExpiracao ([datetime] UTC ou $null), Status
        ('Ok'|'NaoEncontrado'|'Erro'), Fonte ('registro.br'|'rdap.org') e Erro.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Dominio,

        [int] $TimeoutSec = 10,

        [int] $EsperaRetentativaMs = 2000
    )

    $resultado = [ordered] @{
        DataExpiracao = $null
        Status        = $null
        Fonte         = $null
        Erro          = $null
    }

    try {
        $dominioNormalizado = ConvertTo-DominioNormalizado -Dominio $Dominio
    }
    catch {
        $resultado.Status = 'Erro'
        $resultado.Erro = $_.Exception.Message
        return [pscustomobject] $resultado
    }

    if ($dominioNormalizado -match '\.br$') {
        $uri = "https://rdap.registro.br/domain/$dominioNormalizado"
        $resultado.Fonte = 'registro.br'
    }
    else {
        $uri = "https://rdap.org/domain/$dominioNormalizado"
        $resultado.Fonte = 'rdap.org'
    }

    $maximoTentativas = 2
    $resposta = $null
    $tentativa = 0

    while ($tentativa -lt $maximoTentativas) {
        $tentativa++
        try {
            $resposta = Invoke-RestMethod -Uri $uri -Method Get -TimeoutSec $TimeoutSec -ErrorAction Stop
            break
        }
        catch {
            $codigoStatus = Get-CodigoStatusHttp -Excecao $_.Exception

            if ($codigoStatus -eq 429 -and $tentativa -lt $maximoTentativas) {
                Start-Sleep -Milliseconds $EsperaRetentativaMs
                continue
            }

            if ($codigoStatus -eq 404) {
                $resultado.Status = 'NaoEncontrado'
                return [pscustomobject] $resultado
            }

            $resultado.Status = 'Erro'
            $resultado.Erro = $_.Exception.Message
            return [pscustomobject] $resultado
        }
    }

    $eventoExpiracao = $resposta.events | Where-Object { $_.eventAction -eq 'expiration' } | Select-Object -First 1
    if (-not $eventoExpiracao) {
        $resultado.Status = 'Erro'
        $resultado.Erro = 'Resposta RDAP sem evento de expiração (eventAction=expiration).'
        return [pscustomobject] $resultado
    }

    $estilos = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
    $resultado.DataExpiracao = [datetime]::Parse($eventoExpiracao.eventDate, [System.Globalization.CultureInfo]::InvariantCulture, $estilos)
    $resultado.Status = 'Ok'

    return [pscustomobject] $resultado
}

Export-ModuleMember -Function @(
    'ConvertTo-DominioNormalizado'
    'Get-VencimentoDominio'
)
