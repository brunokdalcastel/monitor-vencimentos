#Requires -Version 5.1
# Módulo Identidade — token de acesso via Managed Identity (T05, reaproveitado na T06).
# Compatível com PowerShell 7.4 (Functions) e Windows PowerShell 5.1.

Set-StrictMode -Version Latest

$script:CacheTokens = @{}

function Get-TokenAcesso {
    <#
    .SYNOPSIS
        Obtém (e mantém em cache) um token de acesso da Managed Identity para um recurso do Azure.
    .DESCRIPTION
        Usa o protocolo de identidade do App Service/Functions (`IDENTITY_ENDPOINT` +
        `IDENTITY_HEADER`, api-version 2019-08-01). O token é mantido em cache por
        `Recurso` até perto de expirar (margem configurável), evitando uma chamada
        de rede por invocação.
    .PARAMETER Recurso
        URI do recurso do Azure para o qual o token é emitido (ex.: 'https://storage.azure.com',
        'https://communication.azure.com').
    .PARAMETER MargemExpiracaoSegundos
        Quantos segundos antes do vencimento real o token é considerado expirado,
        para não usar um token prestes a vencer no meio de uma chamada. Padrão 300 (5min).
    .OUTPUTS
        string — o access_token (JWT).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $Recurso,

        [int] $MargemExpiracaoSegundos = 300
    )

    $agora = [DateTimeOffset]::UtcNow

    if ($script:CacheTokens.ContainsKey($Recurso)) {
        $cache = $script:CacheTokens[$Recurso]
        if ($agora -lt $cache.ExpiraEm) {
            return $cache.Token
        }
    }

    $identityEndpoint = $env:IDENTITY_ENDPOINT
    $identityHeader = $env:IDENTITY_HEADER
    if (-not $identityEndpoint -or -not $identityHeader) {
        throw 'IDENTITY_ENDPOINT/IDENTITY_HEADER não configurados — Managed Identity indisponível neste ambiente.'
    }

    $separador = if ($identityEndpoint.Contains('?')) { '&' } else { '?' }
    $uri = "$identityEndpoint${separador}resource=$([uri]::EscapeDataString($Recurso))&api-version=2019-08-01"

    $resposta = Invoke-RestMethod -Uri $uri -Method Get -Headers @{ 'X-IDENTITY-HEADER' = $identityHeader } -ErrorAction Stop

    $expiraEm = [DateTimeOffset]::FromUnixTimeSeconds([long] $resposta.expires_on).AddSeconds(-$MargemExpiracaoSegundos)
    $script:CacheTokens[$Recurso] = @{ Token = $resposta.access_token; ExpiraEm = $expiraEm }

    return $resposta.access_token
}

Export-ModuleMember -Function @('Get-TokenAcesso')
