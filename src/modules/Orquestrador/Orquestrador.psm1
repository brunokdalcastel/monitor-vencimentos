#Requires -Version 5.1
# Módulo Orquestrador — verificação diária de vencimentos (T07).
# Amarra os módulos Vencimentos (T02), Ssl (T03), Dominio (T04), Storage (T05) e
# Email (T06). A Function (T08) só chama Invoke-VerificacaoDiaria.
# Compatível com PowerShell 7.4 (Functions) e Windows PowerShell 5.1.

Set-StrictMode -Version Latest

Import-Module "$PSScriptRoot/../Vencimentos/Vencimentos.psd1" -Force
Import-Module "$PSScriptRoot/../Ssl/Ssl.psd1" -Force
Import-Module "$PSScriptRoot/../Dominio/Dominio.psd1" -Force
Import-Module "$PSScriptRoot/../Storage/Storage.psd1" -Force
Import-Module "$PSScriptRoot/../Email/Email.psd1" -Force

$script:TabelaItens = 'Itens'
$script:TabelaVerificacoes = 'Verificacoes'
$script:TabelaAlertasEnviados = 'AlertasEnviados'
$script:MesesRetencaoVerificacoes = 12
$script:LimiteFalhasConsecutivas = 3

function Get-PropriedadeOpcional {
    # Acesso seguro a uma propriedade que pode não existir (entidades vindas do
    # Table Storage só têm as propriedades que foram gravadas) — evita erro do
    # Set-StrictMode ao ler campos opcionais (Descricao, Titular, DataVencimento...).
    param(
        [Parameter(Mandatory)]
        [object] $Objeto,

        [Parameter(Mandatory)]
        [string] $Nome
    )

    $propriedade = $Objeto.PSObject.Properties[$Nome]
    if ($null -eq $propriedade) {
        return $null
    }
    return $propriedade.Value
}

function ConvertTo-ItemDoStorage {
    # Uma entidade bruta da tabela Itens (PK=ClienteId, RK=ItemId, ver
    # docs/especificacao.md) não repete ClienteId/ItemId como colunas — o
    # ConvertTo-ItemNormalizado (módulo Vencimentos) espera esses campos, então
    # são preenchidos aqui a partir de PartitionKey/RowKey antes de normalizar.
    param(
        [Parameter(Mandatory)]
        [object] $EntidadeBruta
    )

    $paraNormalizar = [pscustomobject] @{
        ClienteId      = $EntidadeBruta.PartitionKey
        ItemId         = $EntidadeBruta.RowKey
        Tipo           = Get-PropriedadeOpcional $EntidadeBruta 'Tipo'
        Alvo           = Get-PropriedadeOpcional $EntidadeBruta 'Alvo'
        Descricao      = Get-PropriedadeOpcional $EntidadeBruta 'Descricao'
        Titular        = Get-PropriedadeOpcional $EntidadeBruta 'Titular'
        DataVencimento = Get-PropriedadeOpcional $EntidadeBruta 'DataVencimento'
        ContatosAlerta = Get-PropriedadeOpcional $EntidadeBruta 'ContatosAlerta'
        Ativo          = Get-PropriedadeOpcional $EntidadeBruta 'Ativo'
    }

    return ConvertTo-ItemNormalizado -Item $paraNormalizar
}

function Invoke-VerificacaoItem {
    # Despacha a verificação por Tipo (ver fluxo da T07 no PLANO.md) e devolve
    # sempre (nunca lança): Sucesso, DataVencimento ('yyyy-MM-dd' ou $null), Erro,
    # Automatica (se DataVencimento pode ser regravada no item) e Ignorar (CertA1
    # sem dado do agente ainda — Fase 2 não existe; não é falha, só não há o que
    # verificar por enquanto).
    param(
        [Parameter(Mandatory)]
        [object] $Item
    )

    $resultado = [ordered] @{
        Sucesso        = $false
        DataVencimento = $null
        Erro           = $null
        Automatica     = $false
        Ignorar        = $false
    }

    switch ($Item.Tipo) {
        'SSL' {
            $resultado.Automatica = $true
            try {
                $endereco = ConvertTo-EnderecoSsl -Alvo $Item.Alvo
                $certificado = Get-CertificadoSsl -Host $endereco.Host -Porta $endereco.Porta
                if ($certificado.Erro) {
                    $resultado.Erro = $certificado.Erro
                }
                else {
                    $resultado.Sucesso = $true
                    $resultado.DataVencimento = $certificado.NotAfter.Date.ToString('yyyy-MM-dd')
                }
            }
            catch {
                $resultado.Erro = $_.Exception.Message
            }
        }
        'Dominio' {
            $resultado.Automatica = $true
            try {
                $vencimento = Get-VencimentoDominio -Dominio $Item.Alvo
                if ($vencimento.Status -ne 'Ok') {
                    $resultado.Erro = if ($vencimento.Erro) { $vencimento.Erro } else { "RDAP: $($vencimento.Status)" }
                }
                else {
                    $resultado.Sucesso = $true
                    $resultado.DataVencimento = $vencimento.DataExpiracao.Date.ToString('yyyy-MM-dd')
                }
            }
            catch {
                $resultado.Erro = $_.Exception.Message
            }
        }
        { $_ -in @('CertA3', 'Manual') } {
            if ($Item.DataVencimento) {
                $resultado.Sucesso = $true
                $resultado.DataVencimento = $Item.DataVencimento
            }
            else {
                $resultado.Erro = 'DataVencimento não cadastrada.'
            }
        }
        'CertA1' {
            # Fase 2 (agente) ainda não existe: sem DataVencimento recebida do
            # agente, não há o que verificar — não conta como falha.
            if ($Item.DataVencimento) {
                $resultado.Sucesso = $true
                $resultado.DataVencimento = $Item.DataVencimento
            }
            else {
                $resultado.Ignorar = $true
            }
        }
        default {
            $resultado.Erro = "Tipo não suportado: '$($Item.Tipo)'."
        }
    }

    return [pscustomobject] $resultado
}

function Get-ContagemFalhasConsecutivas {
    # Conta quantas verificações seguidas (incluindo a de hoje, já gravada) deram
    # erro para o item — usado para o aviso explícito ao admin após 3 falhas
    # seguidas (ver regra de marcos no PLANO.md).
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = "Devolve a CONTAGEM (singular, um int) de falhas consecutivas — 'Falhas' no plural é o termo certo aqui.")]
    param(
        [Parameter(Mandatory)]
        [string] $ItemId
    )

    $filtro = "PartitionKey eq '$(ConvertTo-ValorFiltroOData -Valor $ItemId)'"
    $historico = Get-Entidades -Tabela $script:TabelaVerificacoes -Filtro $filtro
    $ordenado = $historico | Sort-Object -Property RowKey -Descending

    $contagem = 0
    foreach ($registro in $ordenado) {
        if ((Get-PropriedadeOpcional $registro 'Sucesso') -eq $false) {
            $contagem++
        }
        else {
            break
        }
    }
    return $contagem
}

function Remove-VerificacaoAntiga {
    # Limpeza de Verificacoes com mais de 12 meses (regra da T07). RowKey é a
    # data yyyyMMdd, então a comparação lexicográfica (zero-padded) basta.
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [datetime] $Hoje
    )

    $limite = $Hoje.AddMonths(-$script:MesesRetencaoVerificacoes).ToString('yyyyMMdd')
    $todos = Get-Entidades -Tabela $script:TabelaVerificacoes
    foreach ($registro in $todos) {
        if ([string] $registro.RowKey -lt $limite) {
            if ($PSCmdlet.ShouldProcess("$($registro.PartitionKey)/$($registro.RowKey)", 'Remover verificação antiga (> 12 meses)')) {
                Remove-Entidade -Tabela $script:TabelaVerificacoes -PartitionKey $registro.PartitionKey -RowKey $registro.RowKey
            }
        }
    }
}

function Invoke-VerificacaoDiaria {
    <#
    .SYNOPSIS
        Executa a verificação diária de vencimentos: verifica, alerta e resume ao admin.
    .DESCRIPTION
        Fluxo (ver T07 no PLANO.md): lê Itens ativos → verifica cada um por Tipo →
        grava Verificacoes (idempotente por dia) → atualiza DataVencimento
        automática → calcula o marco devido → agrupa itens pendentes por contato
        (D7, um e-mail por contato) → envia → grava AlertasEnviados só após envio
        bem-sucedido para TODOS os contatos do item → limpa Verificacoes antigas →
        envia o resumo ao ADMIN_EMAIL. Erro em um item nunca interrompe os demais.
    .PARAMETER Hoje
        Data de referência (fuso America/Sao_Paulo). Padrão: Get-DataHojeBrasil.
    .OUTPUTS
        pscustomobject com TotalItensVerificados, AlertasEnviados e Falhas.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [datetime] $Hoje = (Get-DataHojeBrasil)
    )

    New-TabelaSeNaoExistir -Tabela $script:TabelaItens
    New-TabelaSeNaoExistir -Tabela $script:TabelaVerificacoes
    New-TabelaSeNaoExistir -Tabela $script:TabelaAlertasEnviados

    $totalItensVerificados = 0
    $falhas = New-Object System.Collections.Generic.List[object]
    $itensPendentesAlerta = New-Object System.Collections.Generic.List[object]

    $itensAtivos = Get-Entidades -Tabela $script:TabelaItens -Filtro 'Ativo eq true'
    $alertasEnviadosExistentes = Get-Entidades -Tabela $script:TabelaAlertasEnviados

    foreach ($entidadeBruta in $itensAtivos) {
        $totalItensVerificados++

        try {
            $item = ConvertTo-ItemDoStorage -EntidadeBruta $entidadeBruta
        }
        catch {
            $falhas.Add([pscustomobject] @{
                    Tipo = [string] (Get-PropriedadeOpcional $entidadeBruta 'Tipo')
                    Alvo = [string] (Get-PropriedadeOpcional $entidadeBruta 'Alvo')
                    Erro = $_.Exception.Message
                })
            continue
        }

        $verificacao = Invoke-VerificacaoItem -Item $item
        if ($verificacao.Ignorar) {
            continue
        }

        Set-Entidade -Tabela $script:TabelaVerificacoes -Entidade ([ordered] @{
                PartitionKey   = $item.ItemId
                RowKey         = $Hoje.ToString('yyyyMMdd')
                Tipo           = $item.Tipo
                Alvo           = $item.Alvo
                DataVencimento = $verificacao.DataVencimento
                Sucesso        = $verificacao.Sucesso
                Erro           = $verificacao.Erro
            })

        if (-not $verificacao.Sucesso) {
            $falhasConsecutivas = Get-ContagemFalhasConsecutivas -ItemId $item.ItemId
            $textoErro = $verificacao.Erro
            if ($falhasConsecutivas -ge $script:LimiteFalhasConsecutivas) {
                $textoErro = "$textoErro (ATENÇÃO: $falhasConsecutivas verificações seguidas falharam)"
            }
            $falhas.Add([pscustomobject] @{ Tipo = $item.Tipo; Alvo = $item.Alvo; Erro = $textoErro })
            continue
        }

        if ($verificacao.Automatica) {
            Set-Entidade -Tabela $script:TabelaItens -Entidade ([ordered] @{
                    PartitionKey   = $entidadeBruta.PartitionKey
                    RowKey         = $entidadeBruta.RowKey
                    Tipo           = $item.Tipo
                    Alvo           = $item.Alvo
                    Descricao      = $item.Descricao
                    Titular        = $item.Titular
                    DataVencimento = $verificacao.DataVencimento
                    ContatosAlerta = ($item.ContatosAlerta -join ';')
                    Ativo          = $item.Ativo
                })
        }

        $diasRestantes = Get-DiasRestantes -DataVencimento $verificacao.DataVencimento -Hoje $Hoje
        $marco = Get-MarcoDevido -DiasRestantes $diasRestantes
        if ($null -eq $marco) {
            continue
        }

        if (Test-AlertaPendente -ItemId $item.ItemId -DataVencimento $verificacao.DataVencimento -Marco $marco -AlertasEnviados $alertasEnviadosExistentes) {
            $itensPendentesAlerta.Add([pscustomobject] @{
                    ItemId         = $item.ItemId
                    Contatos       = $item.ContatosAlerta
                    Tipo           = $item.Tipo
                    Alvo           = $item.Alvo
                    DataVencimento = $verificacao.DataVencimento
                    Marco          = $marco
                })
        }
    }

    # D7: um e-mail consolidado por contato por dia (agrupa os itens pendentes por contato).
    $porContato = [ordered] @{}
    foreach ($pendente in $itensPendentesAlerta) {
        foreach ($contato in $pendente.Contatos) {
            if (-not $porContato.Contains($contato)) {
                $porContato[$contato] = New-Object System.Collections.Generic.List[object]
            }
            $porContato[$contato].Add($pendente)
        }
    }

    # Só grava AlertasEnviados (D8) para um item quando TODOS os seus contatos
    # receberam o e-mail com sucesso — falha parcial refaz a tentativa completa
    # no próximo dia (o marco continua pendente para o item), sem duplicar envio
    # para quem já recebeu porque o Test-AlertaPendente é por ItemId+Marco, não
    # por contato.
    $sucessoPorItem = [ordered] @{}
    foreach ($pendente in $itensPendentesAlerta) {
        $sucessoPorItem[$pendente.ItemId] = $true
    }

    $resumoAlertasEnviados = New-Object System.Collections.Generic.List[object]

    foreach ($contato in $porContato.Keys) {
        $itensDoContato = $porContato[$contato]
        $itensParaEmail = $itensDoContato | ForEach-Object {
            [pscustomobject] @{ Tipo = $_.Tipo; Alvo = $_.Alvo; DataVencimento = $_.DataVencimento; Marco = $_.Marco }
        }
        $email = New-EmailAlerta -Contato $contato -Itens $itensParaEmail

        try {
            Send-EmailAcs -Para $contato -Assunto $email.Assunto -Html $email.Html -Texto $email.Texto | Out-Null
            $resumoAlertasEnviados.Add([pscustomobject] @{ Contato = $contato; TotalItens = $itensDoContato.Count })
        }
        catch {
            foreach ($pendente in $itensDoContato) {
                $sucessoPorItem[$pendente.ItemId] = $false
            }
            $falhas.Add([pscustomobject] @{ Tipo = 'Email'; Alvo = $contato; Erro = "Falha ao enviar alerta: $($_.Exception.Message)" })
        }
    }

    $itemJaGravado = [ordered] @{}
    foreach ($pendente in $itensPendentesAlerta) {
        $chave = "$($pendente.ItemId)|$($pendente.Marco)"
        if ($itemJaGravado.Contains($chave)) {
            continue
        }
        if ($sucessoPorItem[$pendente.ItemId]) {
            # $pendente.DataVencimento já está normalizada como 'yyyy-MM-dd' (ver
            # Invoke-VerificacaoItem / ConvertTo-ItemNormalizado) — só remove os
            # traços para compor a RowKey.
            $dataVencimentoTexto = $pendente.DataVencimento -replace '-', ''
            Set-Entidade -Tabela $script:TabelaAlertasEnviados -Entidade ([ordered] @{
                    PartitionKey   = $pendente.ItemId
                    RowKey         = "$dataVencimentoTexto-$($pendente.Marco)"
                    ItemId         = $pendente.ItemId
                    DataVencimento = $pendente.DataVencimento
                    Marco          = $pendente.Marco
                    DataEnvio      = $Hoje.ToString('yyyy-MM-dd')
                })
            $itemJaGravado[$chave] = $true
        }
    }

    Remove-VerificacaoAntiga -Hoje $Hoje

    $adminEmail = $env:ADMIN_EMAIL
    if ($adminEmail) {
        $resumo = New-EmailResumoAdmin -Data $Hoje -TotalItensVerificados $totalItensVerificados `
            -AlertasEnviados $resumoAlertasEnviados.ToArray() -Falhas $falhas.ToArray()
        Send-EmailAcs -Para $adminEmail -Assunto $resumo.Assunto -Html $resumo.Html -Texto $resumo.Texto | Out-Null
    }

    return [pscustomobject] @{
        TotalItensVerificados = $totalItensVerificados
        AlertasEnviados       = $resumoAlertasEnviados.ToArray()
        Falhas                = $falhas.ToArray()
    }
}

Export-ModuleMember -Function @(
    'Invoke-VerificacaoDiaria'
)
