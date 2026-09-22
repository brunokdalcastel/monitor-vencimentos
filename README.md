# Monitor de Vencimentos

Monitoramento automático de vencimentos de certificados digitais ICP-Brasil (A1/A3), certificados SSL e domínios, com alertas escalonados por e-mail (30, 15, 7 e 0 dias).

> Status: em desenvolvimento (Fase 1 — MVP). Roteiro de execução em [`PLANO.md`](PLANO.md). Especificação completa em [`docs/especificacao.md`](docs/especificacao.md).

## O que faz

- Verifica diariamente a validade de certificados SSL (conexão TLS na porta 443).
- Verifica a validade de domínios via RDAP (Registro.br para `.br`, `rdap.org` para os demais).
- Permite cadastrar certificados A3 e itens manuais com data de vencimento conhecida.
- Envia um e-mail consolidado por contato quando um item atinge um marco de alerta (30, 15, 7 ou 0 dias, e repetição semanal após vencido).
- Registra o histórico de verificações e de alertas enviados para evitar duplicidade.

## O que **não** faz

- **Nunca** coleta, registra ou transmite chave privada, arquivo `.pfx` ou senha de certificado — apenas metadados (emissor, validade, thumbprint, etc.).
- Não armazena segredos no repositório (produção usa Managed Identity; `local.settings.json` fica fora do controle de versão).

## Arquitetura

Veja o diagrama e os componentes em [`docs/arquitetura.md`](docs/arquitetura.md). Decisões de projeto (D1–D12) estão registradas como ADRs em [`docs/decisoes/`](docs/decisoes/).

## Stack

- Azure Functions (Flex Consumption, Linux) em PowerShell 7.4.
- Azure Table Storage (acesso via REST, sem módulos Az/AzTable).
- Azure Communication Services — Email.
- Terraform (`azurerm` 4.x) para toda a infraestrutura.
- GitHub Actions com OIDC para CI/CD.

## Rodando localmente

> Passo a passo detalhado será adicionado na T08/T11. Pré-requisitos: PowerShell 7.4+, Azure Functions Core Tools v4, Azurite, Pester 5, PSScriptAnalyzer.

```powershell
Invoke-Pester ./tests -ExcludeTag Integration
Invoke-ScriptAnalyzer -Path ./src, ./agent, ./tools -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
azurite --location .azurite --silent
func start --script-root src/functions
```

## Segurança e privacidade

Consulte [`docs/privacidade.md`](docs/privacidade.md) (a ser criado na T11) e a seção "Segurança (inegociável)" em [`CLAUDE.md`](CLAUDE.md).

## Estrutura do repositório

```
monitor-vencimentos/
├── README.md
├── docs/
│   ├── arquitetura.md
│   ├── decisoes/            # ADRs (registro de decisões)
│   ├── especificacao.md
│   └── privacidade.md
├── infra/                   # Terraform
│   ├── main.tf
│   ├── variables.tf
│   └── environments/{dev,prod}.tfvars
├── src/
│   ├── functions/
│   │   ├── VerificacaoDiaria/   # timer trigger
│   │   └── ReceberAgente/       # HTTP trigger (fase 2)
│   └── modules/                 # funções PowerShell compartilhadas
├── agent/                   # script do agente A1 + instalador (fase 2)
├── tests/                   # Pester
└── .github/workflows/       # lint (PSScriptAnalyzer), testes, deploy
```
