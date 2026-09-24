#Requires -Version 5.1
<#
.SYNOPSIS
    Prepara o ambiente local: sobe o Azurite, cria as tabelas e importa o
    inventário de exemplo. Ver README para o passo a passo completo.
.DESCRIPTION
    Sobe o Azurite completo (blob, queue e table) — não só o serviço de tabelas:
    o próprio host do Azure Functions precisa de blob/queue para o
    AzureWebJobsStorage (estado interno do timer trigger, entre outros), mesmo
    esse projeto só usando tabelas diretamente (ver ADR 0002). Usa as portas
    11000 (blob) e 11001 (queue) em vez das portas padrão (10000/10001) para não
    brigar com outra instância do Azurite que porventura já esteja rodando na
    máquina; a porta de tabelas continua a padrão (10002).
.PARAMETER SemImportar
    Pula a importação de tools/itens-exemplo.csv (útil se você já tem itens cadastrados
    e só quer religar o Azurite).
.EXAMPLE
    ./tools/Start-Local.ps1
    copy src\functions\local.settings.json.example src\functions\local.settings.json
    func start --script-root src/functions
#>
[CmdletBinding()]
param(
    [switch] $SemImportar
)

Set-StrictMode -Version Latest

$raiz = (Resolve-Path "$PSScriptRoot/..").Path
$diretorioAzurite = Join-Path $raiz '.azurite'

if (-not (Get-Command azurite -ErrorAction SilentlyContinue)) {
    throw "azurite não encontrado no PATH. Instale com: npm install -g azurite"
}

if (-not (Test-Path -LiteralPath $diretorioAzurite)) {
    New-Item -ItemType Directory -Path $diretorioAzurite -Force | Out-Null
}

Write-Information 'Iniciando o Azurite (blob:11000, queue:11001, table:10002) em segundo plano...' -InformationAction Continue
# cmd.exe /c em vez de -FilePath azurite direto: o azurite do npm é um .cmd, e o
# Start-Process nem sempre consegue iniciar um .cmd diretamente no Windows.
Start-Process -FilePath 'cmd.exe' -ArgumentList @(
    '/c', 'azurite',
    '--location', $diretorioAzurite,
    '--silent',
    '--blobPort', '11000',
    '--queuePort', '11001',
    '--tablePort', '10002'
) -WindowStyle Hidden
Start-Sleep -Seconds 5

$env:TABELAS_ENDPOINT = 'http://127.0.0.1:10002/devstoreaccount1'
$env:TABELAS_MODO_AUTH = 'SharedKey'
$env:TABELAS_CONTA = 'devstoreaccount1'
$env:TABELAS_CHAVE = 'Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw=='

Import-Module "$raiz/src/modules/Storage/Storage.psd1" -Force

Write-Information 'Criando as tabelas (Itens, Verificacoes, AlertasEnviados, Clientes)...' -InformationAction Continue
foreach ($tabela in @('Itens', 'Verificacoes', 'AlertasEnviados', 'Clientes')) {
    New-TabelaSeNaoExistir -Tabela $tabela
}

if (-not $SemImportar) {
    Write-Information 'Importando itens de exemplo (tools/itens-exemplo.csv)...' -InformationAction Continue
    & "$raiz/tools/Import-Itens.ps1" -CaminhoCsv "$raiz/tools/itens-exemplo.csv"
}

Write-Information '' -InformationAction Continue
Write-Information 'Ambiente local pronto. Para rodar a Function:' -InformationAction Continue
Write-Information '  1. copy src\functions\local.settings.json.example src\functions\local.settings.json' -InformationAction Continue
Write-Information '  2. func start --script-root src/functions' -InformationAction Continue
Write-Information '' -InformationAction Continue
Write-Information 'O timer só dispara às 08:00 (horário de Brasília) por padrão. Para forçar uma' -InformationAction Continue
Write-Information 'execução imediata (com o func start já rodando), num outro terminal:' -InformationAction Continue
Write-Information '  curl -X POST http://localhost:7071/admin/functions/VerificacaoDiaria -H "Content-Type: application/json" -d "{}"' -InformationAction Continue
Write-Information '' -InformationAction Continue
Write-Information 'Os e-mails gerados (EMAIL_MODO=Arquivo) aparecem em saida-emails/.' -InformationAction Continue
