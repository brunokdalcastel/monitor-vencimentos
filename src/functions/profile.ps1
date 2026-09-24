# profile.ps1 — executado uma vez por cold start do worker PowerShell (ver T08 no PLANO.md).
# Importa o orquestrador (que por sua vez importa Vencimentos/Ssl/Dominio/Storage/Email),
# deixando Invoke-VerificacaoDiaria disponível para qualquer função sem reimportar em cada execução.
#
# Dois layouts possíveis para o caminho do módulo, por isso o fallback:
# - Local (`func start --script-root src/functions`): modules/ é irmã de functions/ no
#   repositório (ver docs/especificacao.md, seção 9) → "../modules".
# - Implantado (T10, deploy.yml): o pacote empacota modules/ dentro do próprio pacote,
#   junto de profile.ps1 — o zip vira a raiz do site (wwwroot), então não dá pra
#   referenciar algo "acima" dela → "./modules".
$candidatos = @(
    (Join-Path $PSScriptRoot 'modules/Orquestrador/Orquestrador.psd1'),
    (Join-Path $PSScriptRoot '../modules/Orquestrador/Orquestrador.psd1')
)
$manifesto = $candidatos | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $manifesto) {
    throw "Não encontrei o módulo Orquestrador em nenhum dos caminhos esperados: $($candidatos -join ', ')"
}

Import-Module $manifesto -Force
