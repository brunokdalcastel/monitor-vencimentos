#Requires -Version 5.1
# Módulo Email — envio de alertas via Azure Communication Services (ACS) Email (T06).
# Sem SDK/módulo do ACS: REST puro (ver ADR 0001), Managed Identity via módulo Identidade.
# Compatível com PowerShell 7.4 (Functions) e Windows PowerShell 5.1.

Set-StrictMode -Version Latest

Import-Module "$PSScriptRoot/../Identidade/Identidade.psd1" -Force

$script:VersaoApiEmail = '2023-03-31'
$script:OrdemMarcos = @('VENCIDO', '0', '7', '15', '30')
$script:RotulosMarco = @{
    'VENCIDO' = 'Vencido(s)'
    '0'       = 'Vence hoje'
    '7'       = 'Vence em até 7 dias'
    '15'      = 'Vence em até 15 dias'
    '30'      = 'Vence em até 30 dias'
}

function ConvertTo-TextoHtmlSeguro {
    <#
    .SYNOPSIS
        Escapa um texto para uso seguro dentro de HTML.
    .DESCRIPTION
        Todo campo vindo de cadastro (Alvo, contato, etc.) passa por aqui antes de
        entrar no e-mail — regra de segurança do CLAUDE.md.
    .OUTPUTS
        string
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowNull()]
        [string] $Texto
    )

    if ($null -eq $Texto) {
        return ''
    }
    return [System.Net.WebUtility]::HtmlEncode($Texto)
}

function Get-GrupoMarco {
    # Reduz um Marco ('30'|'15'|'7'|'0'|'VENCIDO-n') ao grupo de urgência usado no
    # agrupamento do e-mail ('30'|'15'|'7'|'0'|'VENCIDO').
    param(
        [Parameter(Mandatory)]
        [string] $Marco
    )

    if ($Marco -match '^VENCIDO') {
        return 'VENCIDO'
    }
    return $Marco
}

function ConvertTo-DataObjeto {
    # Aceita [datetime] ou string 'yyyy-MM-dd' e devolve sempre [datetime].
    param(
        [Parameter(Mandatory)]
        [object] $Data
    )

    if ($Data -is [datetime]) {
        return $Data
    }
    return [datetime]::ParseExact([string] $Data, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-DataFormatada {
    # Aceita [datetime] ou string 'yyyy-MM-dd' e devolve 'dd/MM/yyyy'.
    param(
        [Parameter(Mandatory)]
        [object] $Data
    )

    return (ConvertTo-DataObjeto -Data $Data).ToString('dd/MM/yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Group-ItensPorUrgencia {
    # Agrupa e ordena os itens na ordem de urgência (vencidos → 0 → 7 → 15 → 30);
    # dentro de cada grupo, ordena por DataVencimento crescente (mais urgente primeiro).
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Itens
    )

    $porGrupo = @{}
    foreach ($item in $Itens) {
        $grupo = Get-GrupoMarco -Marco ([string] $item.Marco)
        if (-not $porGrupo.ContainsKey($grupo)) {
            $porGrupo[$grupo] = New-Object System.Collections.Generic.List[object]
        }
        $porGrupo[$grupo].Add($item)
    }

    $resultado = New-Object System.Collections.Generic.List[object]
    foreach ($grupo in $script:OrdemMarcos) {
        if (-not $porGrupo.ContainsKey($grupo)) {
            continue
        }
        $ordenados = $porGrupo[$grupo] | Sort-Object -Property { ConvertTo-DataObjeto -Data $_.DataVencimento }
        $resultado.Add([pscustomobject] @{ Grupo = $grupo; Rotulo = $script:RotulosMarco[$grupo]; Itens = @($ordenados) })
    }

    return , $resultado.ToArray()
}

function New-EmailAlerta {
    <#
    .SYNOPSIS
        Monta o e-mail consolidado de alertas de vencimento para um contato (D7).
    .PARAMETER Contato
        E-mail do destinatário (só para exibição no rodapé — quem envia é o chamador).
    .PARAMETER Itens
        Itens pendentes de alerta para esse contato. Cada um precisa de Alvo, Tipo,
        DataVencimento ('yyyy-MM-dd' ou [datetime]) e Marco ('30'|'15'|'7'|'0'|'VENCIDO-n',
        ver Get-MarcoDevido no módulo Vencimentos).
    .OUTPUTS
        pscustomobject com Assunto, Html e Texto.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Não muda estado: só monta o conteúdo do e-mail. Nome definido no PLANO.md (T06).')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Contato,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Itens
    )

    $grupos = Group-ItensPorUrgencia -Itens $Itens
    $total = $Itens.Count
    $assunto = "Monitor de Vencimentos: $total alerta$(if ($total -ne 1) { 's' }) de vencimento"

    $blocosHtml = New-Object System.Collections.Generic.List[string]
    $blocosTexto = New-Object System.Collections.Generic.List[string]

    foreach ($grupo in $grupos) {
        $linhasHtml = New-Object System.Collections.Generic.List[string]
        foreach ($item in $grupo.Itens) {
            $linhasHtml.Add(@"
      <tr>
        <td style="padding:6px 10px;border-bottom:1px solid #e0e0e0;">$(ConvertTo-TextoHtmlSeguro $item.Tipo)</td>
        <td style="padding:6px 10px;border-bottom:1px solid #e0e0e0;">$(ConvertTo-TextoHtmlSeguro $item.Alvo)</td>
        <td style="padding:6px 10px;border-bottom:1px solid #e0e0e0;">$(ConvertTo-DataFormatada $item.DataVencimento)</td>
      </tr>
"@)
        }

        $blocosHtml.Add(@"
    <h3 style="margin:18px 0 6px;">$(ConvertTo-TextoHtmlSeguro $grupo.Rotulo)</h3>
    <table style="border-collapse:collapse;width:100%;font-family:sans-serif;font-size:14px;">
      <tr style="text-align:left;background:#f5f5f5;">
        <th style="padding:6px 10px;">Tipo</th>
        <th style="padding:6px 10px;">Alvo</th>
        <th style="padding:6px 10px;">Vencimento</th>
      </tr>
$($linhasHtml -join "`n")
    </table>
"@)

        $blocosTexto.Add("$($grupo.Rotulo):")
        foreach ($item in $grupo.Itens) {
            $blocosTexto.Add("  - [$($item.Tipo)] $($item.Alvo) — vence em $(ConvertTo-DataFormatada $item.DataVencimento)")
        }
    }

    $html = @"
<html>
  <body style="font-family:sans-serif;color:#222;">
    <h2>Monitor de Vencimentos</h2>
    <p>$total item(ns) precisam da sua atenção:</p>
$($blocosHtml -join "`n")
    <p style="margin-top:24px;font-size:12px;color:#777;">Enviado para: $(ConvertTo-TextoHtmlSeguro $Contato)</p>
  </body>
</html>
"@

    $texto = @"
Monitor de Vencimentos

$total item(ns) precisam da sua atencao:

$($blocosTexto -join "`n")

Enviado para: $Contato
"@

    return [pscustomobject] @{ Assunto = $assunto; Html = $html; Texto = $texto }
}

function New-EmailResumoAdmin {
    <#
    .SYNOPSIS
        Monta o e-mail diário de resumo para o administrador (ADMIN_EMAIL).
    .PARAMETER Data
        Data de referência da execução.
    .PARAMETER TotalItensVerificados
        Quantos itens ativos foram verificados nessa execução.
    .PARAMETER AlertasEnviados
        Alertas enviados com sucesso. Cada um precisa de Contato e TotalItens.
    .PARAMETER Falhas
        Falhas de verificação (não geram alerta ao cliente — ver regra de marcos no
        PLANO.md). Cada uma precisa de Alvo, Tipo e Erro.
    .OUTPUTS
        pscustomobject com Assunto, Html e Texto.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Não muda estado: só monta o conteúdo do e-mail. Nome definido no PLANO.md (T06).')]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [datetime] $Data,

        [Parameter(Mandatory)]
        [int] $TotalItensVerificados,

        [AllowEmptyCollection()]
        [object[]] $AlertasEnviados = @(),

        [AllowEmptyCollection()]
        [object[]] $Falhas = @()
    )

    $dataFormatada = $Data.ToString('dd/MM/yyyy', [System.Globalization.CultureInfo]::InvariantCulture)
    $assunto = "Monitor de Vencimentos: resumo diário de $dataFormatada"

    $linhasAlertasHtml = foreach ($alerta in $AlertasEnviados) {
        @"
      <tr>
        <td style="padding:6px 10px;border-bottom:1px solid #e0e0e0;">$(ConvertTo-TextoHtmlSeguro $alerta.Contato)</td>
        <td style="padding:6px 10px;border-bottom:1px solid #e0e0e0;">$($alerta.TotalItens)</td>
      </tr>
"@
    }

    $linhasFalhasHtml = foreach ($falha in $Falhas) {
        @"
      <tr>
        <td style="padding:6px 10px;border-bottom:1px solid #e0e0e0;">$(ConvertTo-TextoHtmlSeguro $falha.Tipo)</td>
        <td style="padding:6px 10px;border-bottom:1px solid #e0e0e0;">$(ConvertTo-TextoHtmlSeguro $falha.Alvo)</td>
        <td style="padding:6px 10px;border-bottom:1px solid #e0e0e0;">$(ConvertTo-TextoHtmlSeguro $falha.Erro)</td>
      </tr>
"@
    }

    $html = @"
<html>
  <body style="font-family:sans-serif;color:#222;">
    <h2>Monitor de Vencimentos — Resumo de $dataFormatada</h2>
    <p>Itens verificados: <strong>$TotalItensVerificados</strong></p>
    <p>Alertas enviados: <strong>$($AlertasEnviados.Count)</strong></p>
    <p>Falhas de verificação: <strong>$($Falhas.Count)</strong></p>

    <h3>Alertas enviados</h3>
    <table style="border-collapse:collapse;width:100%;font-family:sans-serif;font-size:14px;">
      <tr style="text-align:left;background:#f5f5f5;">
        <th style="padding:6px 10px;">Contato</th>
        <th style="padding:6px 10px;">Itens</th>
      </tr>
$($linhasAlertasHtml -join "`n")
    </table>

    <h3>Falhas de verificação</h3>
    <table style="border-collapse:collapse;width:100%;font-family:sans-serif;font-size:14px;">
      <tr style="text-align:left;background:#f5f5f5;">
        <th style="padding:6px 10px;">Tipo</th>
        <th style="padding:6px 10px;">Alvo</th>
        <th style="padding:6px 10px;">Erro</th>
      </tr>
$($linhasFalhasHtml -join "`n")
    </table>
  </body>
</html>
"@

    $linhasAlertasTexto = foreach ($alerta in $AlertasEnviados) { "  - $($alerta.Contato): $($alerta.TotalItens) item(ns)" }
    $linhasFalhasTexto = foreach ($falha in $Falhas) { "  - [$($falha.Tipo)] $($falha.Alvo): $($falha.Erro)" }

    $texto = @"
Monitor de Vencimentos - Resumo de $dataFormatada

Itens verificados: $TotalItensVerificados
Alertas enviados: $($AlertasEnviados.Count)
Falhas de verificacao: $($Falhas.Count)

Alertas enviados:
$($linhasAlertasTexto -join "`n")

Falhas de verificacao:
$($linhasFalhasTexto -join "`n")
"@

    return [pscustomobject] @{ Assunto = $assunto; Html = $html; Texto = $texto }
}

function Get-CodigoStatusHttp {
    # Extrai o código HTTP de uma exceção do Invoke-WebRequest/Invoke-RestMethod:
    # Response.StatusCode (WebException no 5.1, HttpResponseException no 7.x) e, na
    # falta dele (ex.: exceções simuladas em teste), a mensagem da exceção.
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
    # Lê um cabeçalho de uma resposta do Invoke-WebRequest, cross-versão (string no
    # 5.1, string[] no 7.x).
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

function Write-EmailArquivo {
    # Modo local (EMAIL_MODO=Arquivo): grava o HTML em vez de enviar de verdade.
    param(
        [Parameter(Mandatory)]
        [string] $Para,

        [Parameter(Mandatory)]
        [string] $Html
    )

    $diretorio = if ($env:EMAIL_SAIDA_DIR) { $env:EMAIL_SAIDA_DIR } else { './saida-emails' }
    if (-not (Test-Path -LiteralPath $diretorio)) {
        New-Item -ItemType Directory -Path $diretorio -Force | Out-Null
    }

    $destinatarioSeguro = ($Para -replace '[\\/:*?"<>|]', '_')
    $nomeArquivo = "{0}_{1}.html" -f (Get-Date).ToString('yyyyMMdd-HHmmssfff'), $destinatarioSeguro
    $caminho = Join-Path -Path $diretorio -ChildPath $nomeArquivo

    Set-Content -LiteralPath $caminho -Value $Html -Encoding utf8

    return [pscustomobject] @{ Status = 'Arquivo'; Caminho = $caminho }
}

function Send-EmailAcs {
    <#
    .SYNOPSIS
        Envia um e-mail via Azure Communication Services Email.
    .DESCRIPTION
        REST puro (POST {ACS_ENDPOINT}/emails:send), autenticado por Managed Identity
        (recurso 'https://communication.azure.com', ver ADR 0001). O envio é
        assíncrono: acompanha o cabeçalho Operation-Location até o status virar
        'Succeeded' (ou lança exceção em 'Failed'/timeout).
        Modo local (EMAIL_MODO=Arquivo): grava o HTML em ./saida-emails/ (ou
        EMAIL_SAIDA_DIR) em vez de enviar, e não precisa de ACS_ENDPOINT/ACS_REMETENTE.
    .PARAMETER Para
        E-mail do destinatário.
    .PARAMETER Assunto
        Assunto do e-mail.
    .PARAMETER Html
        Corpo em HTML.
    .PARAMETER Texto
        Corpo em texto puro.
    .PARAMETER TimeoutSegundos
        Tempo máximo esperando o Operation-Location terminar. Padrão 30s.
    .PARAMETER IntervaloPollingMs
        Intervalo entre consultas ao Operation-Location. Padrão 1000ms.
    .OUTPUTS
        pscustomobject com Status ('Succeeded'|'Arquivo') e, no modo Arquivo, Caminho.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = "Falso positivo: 'Acs' termina em 's', não é plural. Nome definido no PLANO.md (T06).")]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string] $Para,

        [Parameter(Mandatory)]
        [string] $Assunto,

        [Parameter(Mandatory)]
        [string] $Html,

        [Parameter(Mandatory)]
        [string] $Texto,

        [int] $TimeoutSegundos = 30,

        [int] $IntervaloPollingMs = 1000
    )

    if ($env:EMAIL_MODO -eq 'Arquivo') {
        return Write-EmailArquivo -Para $Para -Html $Html
    }

    $endpoint = $env:ACS_ENDPOINT
    $remetente = $env:ACS_REMETENTE
    if (-not $endpoint -or -not $remetente) {
        throw 'ACS_ENDPOINT e ACS_REMETENTE são obrigatórios quando EMAIL_MODO != Arquivo.'
    }
    $endpoint = $endpoint.TrimEnd('/')

    $token = Get-TokenAcesso -Recurso 'https://communication.azure.com'
    $cabecalhos = @{ Authorization = "Bearer $token" }

    $corpo = [ordered] @{
        senderAddress = $remetente
        recipients    = @{ to = @(@{ address = $Para }) }
        content       = @{ subject = $Assunto; plainText = $Texto; html = $Html }
    }

    $respostaEnvio = Invoke-WebRequest -Uri "$endpoint/emails:send?api-version=$script:VersaoApiEmail" `
        -Method Post -Headers $cabecalhos -Body ($corpo | ConvertTo-Json -Depth 10) `
        -ContentType 'application/json' -UseBasicParsing -ErrorAction Stop

    $operationLocation = Get-CabecalhoResposta -Resposta $respostaEnvio -Nome 'Operation-Location'
    if (-not $operationLocation) {
        throw 'Resposta do ACS sem cabeçalho Operation-Location.'
    }

    $inicio = Get-Date
    while ($true) {
        $statusResposta = Invoke-RestMethod -Uri $operationLocation -Headers $cabecalhos -Method Get -ErrorAction Stop

        if ($statusResposta.status -eq 'Succeeded') {
            return [pscustomobject] @{ Status = 'Succeeded' }
        }
        if ($statusResposta.status -eq 'Failed') {
            throw "Falha ao enviar e-mail via ACS: $($statusResposta.error.message)"
        }
        if (((Get-Date) - $inicio).TotalSeconds -ge $TimeoutSegundos) {
            throw "Tempo esgotado (${TimeoutSegundos}s) aguardando o envio do e-mail via ACS (status: $($statusResposta.status))."
        }

        Start-Sleep -Milliseconds $IntervaloPollingMs
    }
}

Export-ModuleMember -Function @(
    'ConvertTo-TextoHtmlSeguro'
    'New-EmailAlerta'
    'New-EmailResumoAdmin'
    'Send-EmailAcs'
)
