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

- Azure Functions (Flex Consumption, Linux) em PowerShell 7.6 (ver [ADR 0014](docs/decisoes/0014-powershell-76-no-flex.md)).
- Azure Table Storage (acesso via REST, sem módulos Az/AzTable).
- Azure Communication Services — Email, com domínio gerenciado pelo Azure (sem custo, sem domínio próprio — ver [ADR 0013](docs/decisoes/0013-escopo-pessoal-sem-piloto.md)).
- Terraform (`azurerm` 4.x) para toda a infraestrutura.
- GitHub Actions com OIDC para CI/CD.

Projeto de uso pessoal/portfólio (D13): só existe ambiente `dev`, sem custo relevante
enquanto a infra está parada — ver [`infra/README.md`](infra/README.md) para subir/derrubar.

## Rodando localmente

Pré-requisitos: PowerShell 7.4+, [Azure Functions Core Tools v4](https://learn.microsoft.com/azure/azure-functions/functions-run-local), [Azurite](https://github.com/Azure/Azurite) (`npm install -g azurite`), Pester 5, PSScriptAnalyzer.

1. Suba o Azurite, crie as tabelas e importe o inventário de exemplo (um atalho para os três passos):
   ```powershell
   ./tools/Start-Local.ps1
   ```
   (Sobe o Azurite completo — blob/queue em portas alternativas 11000/11001 para não brigar
   com outra instância já rodando na máquina, tabelas na porta padrão 10002 — cria as
   tabelas `Itens`, `Verificacoes`, `AlertasEnviados`, `Clientes` e importa
   `tools/itens-exemplo.csv`.)

2. Copie o arquivo de configuração local (nunca versionado — contém a chave pública e
   conhecida do Azurite, não um segredo de produção):
   ```powershell
   copy src\functions\local.settings.json.example src\functions\local.settings.json
   ```

3. Suba a Function:
   ```powershell
   func start --script-root src/functions
   ```
   > Se aparecer `You must install or update .NET to run this application` porque só há
   > .NET 9/10 instalado (o worker do PowerShell 7.4 do Core Tools pede 8.0): rode com
   > `$env:DOTNET_ROLL_FORWARD='LatestMajor'; func start --script-root src/functions`.

4. O timer só dispara às 08:00 (horário de Brasília, ver ADR 0006). Para forçar uma
   execução imediata, com o `func start` já rodando, em outro terminal:
   ```powershell
   curl -X POST http://localhost:7071/admin/functions/VerificacaoDiaria -H "Content-Type: application/json" -d '{}'
   ```

5. Os e-mails aparecem (não são enviados de verdade — `EMAIL_MODO=Arquivo`) em
   `src/functions/saida-emails/` como `.html`. Abra um no navegador para conferir.

Para cadastrar seus próprios itens, edite `tools/itens-exemplo.csv` (ou crie outro CSV com
as mesmas colunas) e rode `./tools/Import-Itens.ps1 -CaminhoCsv <arquivo>`.

Testes e lint:

```powershell
Invoke-Pester ./tests -ExcludeTag Integration
Invoke-Pester ./tests -Tag Integration    # precisa do Azurite rodando (e de rede, para SSL/RDAP)
Invoke-ScriptAnalyzer -Path ./src -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Invoke-ScriptAnalyzer -Path ./tools -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
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
├── infra/                   # Terraform (só `dev` — ver ADR 0013)
│   ├── bootstrap/           # state + identidade OIDC do GitHub Actions (manual, 1x)
│   ├── *.tf                 # storage, function, email (ACS), observabilidade, budget...
│   └── environments/dev.tfvars
├── src/
│   ├── functions/
│   │   ├── VerificacaoDiaria/   # timer trigger
│   │   └── ReceberAgente/       # HTTP trigger (fase 2)
│   └── modules/                 # funções PowerShell compartilhadas
├── agent/                   # script do agente A1 + instalador (fase 2)
├── tools/                   # Import-Itens.ps1, Start-Local.ps1, itens-exemplo.csv
├── tests/                   # Pester
└── .github/workflows/       # lint (PSScriptAnalyzer), testes, deploy
```
