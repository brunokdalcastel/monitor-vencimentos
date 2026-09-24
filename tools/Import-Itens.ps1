#Requires -Version 5.1
<#
.SYNOPSIS
    Importa itens de um CSV para a tabela Itens do Table Storage (upsert).
.DESCRIPTION
    Lê um CSV com as colunas da tabela Itens (ClienteId, ItemId, Tipo, Alvo,
    Descricao, Titular, DataVencimento, ContatosAlerta, Ativo — ver
    docs/especificacao.md), valida cada linha com ConvertTo-ItemNormalizado
    (módulo Vencimentos) e grava (InsertOrReplace) via Set-Entidade (módulo
    Storage). Erro numa linha não interrompe as demais; ao final, lista os
    erros encontrados e termina com código de saída 1 se houver algum.

    Requer as variáveis de ambiente do módulo Storage já configuradas
    (TABELAS_ENDPOINT, TABELAS_MODO_AUTH, ...) — ver local.settings.json.example
    ou tools/Start-Local.ps1.
.PARAMETER CaminhoCsv
    Caminho do arquivo CSV a importar.
.EXAMPLE
    ./tools/Import-Itens.ps1 -CaminhoCsv ./tools/itens-exemplo.csv
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $CaminhoCsv
)

Set-StrictMode -Version Latest

Import-Module "$PSScriptRoot/../src/modules/Vencimentos/Vencimentos.psd1" -Force
Import-Module "$PSScriptRoot/../src/modules/Storage/Storage.psd1" -Force

if (-not (Test-Path -LiteralPath $CaminhoCsv)) {
    throw "Arquivo não encontrado: $CaminhoCsv"
}

New-TabelaSeNaoExistir -Tabela 'Itens'

$linhas = @(Import-Csv -LiteralPath $CaminhoCsv)
$totalLinhas = $linhas.Count
$totalImportado = 0
$erros = New-Object System.Collections.Generic.List[string]
$numeroLinha = 1

foreach ($linha in $linhas) {
    $numeroLinha++ # +1 porque a linha 1 do arquivo é o cabeçalho

    try {
        $item = ConvertTo-ItemNormalizado -Item $linha

        if ([string]::IsNullOrWhiteSpace($item.ClienteId)) {
            throw 'ClienteId é obrigatório (vira o PartitionKey do item).'
        }
        if ([string]::IsNullOrWhiteSpace($item.ItemId)) {
            throw 'ItemId é obrigatório (vira o RowKey do item).'
        }

        Set-Entidade -Tabela 'Itens' -Entidade ([ordered] @{
                PartitionKey   = $item.ClienteId
                RowKey         = $item.ItemId
                Tipo           = $item.Tipo
                Alvo           = $item.Alvo
                Descricao      = $item.Descricao
                Titular        = $item.Titular
                DataVencimento = $item.DataVencimento
                ContatosAlerta = ($item.ContatosAlerta -join ';')
                Ativo          = $item.Ativo
            })

        $totalImportado++
        Write-Information "OK  linha ${numeroLinha}: $($item.ItemId) ($($item.Tipo) — $($item.Alvo))" -InformationAction Continue
    }
    catch {
        $mensagem = "Linha ${numeroLinha}: $($_.Exception.Message)"
        $erros.Add($mensagem)
        Write-Warning $mensagem
    }
}

Write-Information '' -InformationAction Continue
Write-Information "Importação concluída: $totalImportado de $totalLinhas item(ns) importado(s)." -InformationAction Continue

if ($erros.Count -gt 0) {
    Write-Information "$($erros.Count) erro(s):" -InformationAction Continue
    foreach ($erro in $erros) {
        Write-Information "  - $erro" -InformationAction Continue
    }
    exit 1
}
