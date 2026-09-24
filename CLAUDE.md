# CLAUDE.md — Monitor de Vencimentos

Monitoramento de vencimentos (SSL, domínios, certificados ICP-Brasil A1/A3) em Azure Functions PowerShell.
Especificação: `docs/especificacao.md` (antes da T01: `projeto-monitor-vencimentos.md`). Roteiro de tarefas: `PLANO.md`.

## Como trabalhar
- Execute **uma tarefa do `PLANO.md` por sessão**, respeitando os critérios de aceite. Não adiante tarefas futuras.
- Siga as decisões D1–D13 do `PLANO.md`. Se precisar contrariar uma, pare e pergunte; se aprovado, registre um novo ADR em `docs/decisoes/`.
- Ao terminar: rode testes e lint, marque a caixa da tarefa no `PLANO.md` e liste pendências.
- Idioma: código com nomes de funções no padrão Verbo-Substantivo aprovado do PowerShell (`Get-`, `Set-`, `New-`, `Test-`, `Invoke-`...) e substantivos em português; comentários, docs e mensagens em português.

## Stack e restrições
- PowerShell **7.4** nas Functions (Flex Consumption, Linux). O agente A1 (Fase 2) precisa rodar em **Windows PowerShell 5.1**.
- **Sem dependências externas** no código da Function: nada de módulos Az/AzTable (managed dependencies não é suportado no Flex). Azure é acessado via REST com `Invoke-RestMethod`.
- Toda a lógica fica em `src/modules/`; os `run.ps1` das Functions só chamam funções do módulo.
- Datas: sempre calcular "hoje" no fuso `America/Sao_Paulo`; gravar datas como `yyyy-MM-dd`.
- Infra só via Terraform em `infra/` (azurerm 4.x). Nada criado manualmente no portal, exceto o descrito no Marco 0.

## Segurança (inegociável)
- Nunca coletar, registrar ou transmitir chave privada, `.pfx` ou senha de certificado.
- Nenhum segredo no repositório. `local.settings.json` fica no `.gitignore`; versionar só o `.example`.
- Produção usa Managed Identity; chave compartilhada do Storage apenas contra Azurite local.
- Escapar em HTML todo campo vindo de cadastro ao montar e-mails; escapar valores em filtros OData.

## Comandos
```powershell
Invoke-Pester ./tests -ExcludeTag Integration          # testes unitários
Invoke-Pester ./tests -Tag Integration                  # integração (rede / Azurite)
Invoke-ScriptAnalyzer -Path ./src, ./agent, ./tools -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
terraform -chdir=infra fmt -check; terraform -chdir=infra validate
azurite --location .azurite --silent                    # Storage local
func start --script-root src/functions                  # Function local
```
(Ajuste os comandos aqui se a estrutura mudar.)

## Testes
- Pester 5. Toda função pública tem teste. Rede e Azure sempre mockados nos unitários (`Mock Invoke-RestMethod`).
- Testes que usam rede real ou Azurite recebem `-Tag Integration`.
