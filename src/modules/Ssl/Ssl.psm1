#Requires -Version 5.1
# Módulo Ssl — verificação de certificado SSL/TLS via conexão direta na porta (T03).
# Compatível com PowerShell 7.4 (Functions) e Windows PowerShell 5.1.

Set-StrictMode -Version Latest

function ConvertTo-EnderecoSsl {
    <#
    .SYNOPSIS
        Extrai host e porta de um Alvo de SSL.
    .DESCRIPTION
        Aceita três formatos, na coluna Alvo do item cadastrado:
        - 'host' → porta padrão (443, ou -PortaPadrao se informado).
        - 'host:porta' → porta explícita.
        - 'https://host[:porta][/caminho...]' → host (e porta, se presente na URL).
    .PARAMETER Alvo
        Texto livre cadastrado no item (coluna Alvo da tabela Itens).
    .PARAMETER PortaPadrao
        Porta usada quando o Alvo não especifica uma. Padrão 443.
    .OUTPUTS
        pscustomobject com Host e Porta.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Alvo,

        [int] $PortaPadrao = 443
    )

    $texto = $Alvo.Trim()
    if ($texto -eq '') {
        throw 'Alvo é obrigatório.'
    }

    # URL com esquema https:// — delega o parsing para [uri], só a porta/host importam aqui.
    if ($texto -match '^https://') {
        $uri = $null
        if (-not [uri]::TryCreate($texto, [UriKind]::Absolute, [ref] $uri) -or $uri.Host -eq '') {
            throw "Alvo inválido: '$Alvo'."
        }
        $porta = if ($uri.IsDefaultPort) { $PortaPadrao } else { $uri.Port }
        return [pscustomobject] @{ Host = $uri.Host; Porta = $porta }
    }

    # 'host' ou 'host:porta'
    $partes = $texto.Split(':')
    if ($partes.Count -gt 2) {
        throw "Alvo inválido: '$Alvo'."
    }

    $hostName = $partes[0].Trim()
    if ($hostName -eq '') {
        throw "Alvo inválido: '$Alvo'."
    }

    $porta = $PortaPadrao
    if ($partes.Count -eq 2) {
        $portaTexto = $partes[1].Trim()
        $portaValor = 0
        $portaOk = [int]::TryParse($portaTexto, [ref] $portaValor)
        if (-not $portaOk -or $portaValor -le 0 -or $portaValor -gt 65535) {
            throw "Porta inválida em Alvo: '$Alvo'."
        }
        $porta = $portaValor
    }

    return [pscustomobject] @{ Host = $hostName; Porta = $porta }
}

function Get-CertificadoSsl {
    <#
    .SYNOPSIS
        Conecta via TLS no host/porta informados e lê os dados do certificado apresentado.
    .DESCRIPTION
        Usa TcpClient + SslStream com SNI (o host de conexão é enviado no ClientHello).
        O callback de validação SEMPRE aceita o certificado — o objetivo é conseguir ler
        certificados já vencidos, autoassinados ou com cadeia inválida; os problemas de
        cadeia encontrados (construída localmente, sem checagem de revogação — determinística
        e sem depender de CRL/OCSP externos) são reportados em ErrosCadeia, não bloqueiam a leitura.
        Erros de conexão/handshake (DNS, timeout, recusa) são capturados em Erro; os demais
        campos ficam $null nesse caso.
    .PARAMETER Host
        Nome do host a conectar (usado também como SNI).
    .PARAMETER Porta
        Porta TCP. Padrão 443.
    .PARAMETER TimeoutMs
        Timeout de conexão TCP em milissegundos. Padrão 10000 (10s).
    .OUTPUTS
        pscustomobject com NotAfter (UTC), Emissor, Assunto, Thumbprint, CadeiaValida,
        ErrosCadeia (string[]) e Erro.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidAssignmentToAutomaticVariable', 'Host', Justification = 'Nome definido no PLANO.md (T03).')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Host,

        [int] $Porta = 443,

        [int] $TimeoutMs = 10000
    )

    $resultado = [ordered] @{
        NotAfter     = $null
        Emissor      = $null
        Assunto      = $null
        Thumbprint   = $null
        CadeiaValida = $null
        ErrosCadeia  = @()
        Erro         = $null
    }

    $errosCadeia = New-Object System.Collections.Generic.List[string]
    $tcpClient = $null
    $sslStream = $null

    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tarefaConexao = $tcpClient.ConnectAsync($Host, $Porta)
        if (-not $tarefaConexao.Wait($TimeoutMs)) {
            throw "Tempo esgotado ao conectar em ${Host}:${Porta} (${TimeoutMs}ms)."
        }

        $callbackValidacao = {
            param($origemChamada, $certificado, $chainRecebida, $erros)
            # $origemChamada e $chainRecebida vêm da assinatura fixa do delegate
            # RemoteCertificateValidationCallback do .NET (4 parâmetros posicionais);
            # não usamos nenhum dos dois — construímos nossa própria cadeia abaixo.
            $null = $origemChamada
            $null = $chainRecebida

            # Cadeia própria, sem checagem de revogação: evita depender de CRL/OCSP externos
            # (rede instável, host sem esses endpoints) e mede só confiança + validade.
            $chainVerificacao = New-Object System.Security.Cryptography.X509Certificates.X509Chain
            $chainVerificacao.ChainPolicy.RevocationMode = [System.Security.Cryptography.X509Certificates.X509RevocationMode]::NoCheck
            $certificado2 = [System.Security.Cryptography.X509Certificates.X509Certificate2] $certificado
            $chainVerificacao.Build($certificado2) | Out-Null

            foreach ($status in $chainVerificacao.ChainStatus) {
                if ($status.Status -ne [System.Security.Cryptography.X509Certificates.X509ChainStatusFlags]::NoError) {
                    $errosCadeia.Add("$($status.Status): $($status.StatusInformation.Trim())")
                }
            }
            if ($erros -band [System.Net.Security.SslPolicyErrors]::RemoteCertificateNameMismatch) {
                $errosCadeia.Add('RemoteCertificateNameMismatch: o certificado não corresponde ao host solicitado.')
            }

            return $true
        }.GetNewClosure()

        $sslStream = New-Object System.Net.Security.SslStream(
            $tcpClient.GetStream(),
            $false,
            $callbackValidacao
        )
        $sslStream.AuthenticateAsClient($Host)

        $certificadoRemoto = [System.Security.Cryptography.X509Certificates.X509Certificate2] $sslStream.RemoteCertificate
        $resultado.NotAfter = $certificadoRemoto.NotAfter.ToUniversalTime()
        $resultado.Emissor = $certificadoRemoto.Issuer
        $resultado.Assunto = $certificadoRemoto.Subject
        $resultado.Thumbprint = $certificadoRemoto.Thumbprint
        $resultado.ErrosCadeia = $errosCadeia.ToArray()
        $resultado.CadeiaValida = ($errosCadeia.Count -eq 0)
    }
    catch {
        $resultado.Erro = $_.Exception.Message
    }
    finally {
        if ($sslStream) { $sslStream.Dispose() }
        if ($tcpClient) { $tcpClient.Dispose() }
    }

    return [pscustomobject] $resultado
}

Export-ModuleMember -Function @(
    'ConvertTo-EnderecoSsl'
    'Get-CertificadoSsl'
)
