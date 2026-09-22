# Plano de Produção — Monitor de Vencimentos

> Base: [projeto-monitor-vencimentos.md](projeto-monitor-vencimentos.md) (especificação).
> Este arquivo é o **roteiro de execução**. Cada tarefa `Txx` foi dimensionada para **uma sessão** do Claude (Sonnet).
> Tarefas marcadas **[HUMANO]** dependem de você (contas, contratos, decisões, portal Azure).

---

## Como executar com o Sonnet

1. Abra uma sessão nova por tarefa (contexto limpo).
2. Use o prompt:
   > Leia `CLAUDE.md` e `PLANO.md`. Execute a tarefa **Txx** seguindo os critérios de aceite. Rode os testes. Ao final, marque a tarefa como concluída no `PLANO.md` e liste o que ficou pendente.
3. Revise o diff, faça o commit (ou peça o commit) e só então passe para a próxima.
4. Respeite a ordem: cada tarefa depende das anteriores, salvo onde indicado "pode rodar em paralelo".

---

## Decisões adotadas (padrões — mude antes de começar se discordar)

Cada uma vira um ADR em `docs/decisoes/` na T01.

| # | Decisão | Escolha padrão | Motivo |
|---|---|---|---|
| D1 | Envio de e-mail | **ACS Email**, autenticado por **Managed Identity** via REST | Sem segredo; domínio gerenciado pelo Azure no `dev`, domínio próprio no `prod` |
| D2 | Acesso ao Table Storage | **Wrapper REST próprio** (`Invoke-RestMethod`) — sem módulos Az/AzTable | Flex Consumption **não suporta managed dependencies**; zero dependências = pacote simples e testável |
| D3 | Autenticação | Prod: token da Managed Identity (`IDENTITY_ENDPOINT`). Local: **SharedKey** contra Azurite | Mesmo código nos dois ambientes |
| D4 | Plano da Function | **Flex Consumption**, PowerShell **7.4**, Linux | Cota gratuita, identidade em tudo. Fallback: Consumption (Windows) |
| D5 | Região | **Brazil South** (validar disponibilidade do Flex na T09; fallback East US 2) | Dados no Brasil é argumento de venda |
| D6 | Horário | Timer `0 0 11 * * *` (UTC) = **08:00 BRT**; cálculo de dias no fuso `America/Sao_Paulo` | Flex/Linux não aceita `WEBSITE_TIME_ZONE` |
| D7 | Alertas | **Um e-mail consolidado por contato por dia** (não um por item) | Menos ruído, menos custo |
| D8 | Deduplicação | Chave de `AlertasEnviados` = `ItemId` + `DataVencimento` + `Marco` | Renovou → data muda → ciclo de alertas reinicia sozinho |
| D9 | Item vencido | Alerta "VENCIDO" no dia 0 e **repetição a cada 7 dias** enquanto `Ativo=true` | Não deixar item vencido esquecido |
| D10 | Cadastro de A3/Manual no MVP | **CSV + script** `tools/Import-Itens.ps1` | Portal só na Fase 3 |
| D11 | IaC / CI | Terraform (azurerm 4.x) com state em Storage separado; GitHub Actions com OIDC | Conforme especificação |
| D12 | Domínios não-.br | RDAP via bootstrap IANA (`https://rdap.org/domain/<d>`); `.br` direto no Registro.br | Cobre clientes com `.com` |

### Regra de marcos (D7–D9) — referência para T02

- `DiasRestantes` = data de vencimento − hoje (ambos no fuso de São Paulo, só a data).
- Marcos: `30`, `15`, `7`, `0`, e `VENCIDO` (dias < 0).
- Marco devido = o **mais urgente** já alcançado (ex.: 12 dias → marco `15`; 5 dias → `7`).
- Envia se o marco devido ainda **não** consta em `AlertasEnviados` para aquele `ItemId`+`DataVencimento`.
- Item cadastrado tarde (ex.: faltando 10 dias) recebe só o marco `15`, não o `30` retroativo.
- `VENCIDO`: RowKey inclui a semana (`VENCIDO-<n>` com n = floor(|dias|/7)) para repetir semanalmente.
- Falha de verificação (SSL não conecta, RDAP fora) **não** gera alerta ao cliente; vai para o resumo do admin. Após **3 falhas seguidas**, avisa o admin explicitamente.

---

## Marco 0 — Preparação [HUMANO]

Nada de código antes disto.

- [ ] **M0.1** Conferir contrato de trabalho (exclusividade, não concorrência, propriedade intelectual). Usar equipamento, conta e horário próprios.
- [ ] **M0.2** Assinatura Azure pessoal + **Budget com alerta** (ex.: US$ 10/mês, alertas a 50/80/100%).
- [ ] **M0.3** Conta GitHub e repositório **privado** `monitor-vencimentos` (vazio).
- [ ] **M0.4** Instalar localmente: PowerShell 7.4+, Azure Functions Core Tools v4, Azurite (`npm i -g azurite`), Terraform ≥ 1.9, Azure CLI, Git, Pester 5 e PSScriptAnalyzer (`Install-Module Pester, PSScriptAnalyzer -Scope CurrentUser`).
- [ ] **M0.5** Revisar a tabela de decisões acima e ajustar o que quiser.
- [ ] **M0.6** (pode esperar até o prod) Domínio próprio para envio de e-mail.

---

## Fase 1 — MVP

### T01 — Estrutura do repositório ✅ Concluída (2026-09-22)
**Entrega:** `git init`, estrutura da seção 9 da especificação, `.gitignore` (PowerShell, Terraform, `local.settings.json`, `.azurite/`), `README.md` inicial, `docs/arquitetura.md` (copiar diagrama da especificação), ADRs `0001`…`0012` (um por decisão D1–D12, formato curto: contexto / decisão / consequências), mover a especificação para `docs/especificacao.md` (e atualizar o caminho no `CLAUDE.md`), `PSScriptAnalyzerSettings.psd1` na raiz.
**Aceite:** árvore de pastas criada; `git status` limpo após commit inicial; nenhum segredo versionado.
**Pendências:** nenhuma. O caminho da especificação no `CLAUDE.md` já apontava para `docs/especificacao.md`, então não precisou de alteração. `docs/privacidade.md` (previsto na estrutura da seção 9) será criado na T11, conforme o plano. Repositório remoto no GitHub (`monitor-vencimentos`, privado) é tarefa do Marco 0 [HUMANO] — este commit está só local até lá.

### T02 — Módulo de regras (lógica pura) + Pester
**Arquivo:** `src/modules/Vencimentos/Vencimentos.psm1` (+ `.psd1`).
**Funções:**
- `Get-DataHojeBrasil` → `[datetime]` só a data no fuso `America/Sao_Paulo` (aceita `-Agora` para teste).
- `Get-DiasRestantes -DataVencimento -Hoje`
- `Get-MarcoDevido -DiasRestantes` → `30|15|7|0|VENCIDO-n|$null`
- `Test-AlertaPendente -ItemId -DataVencimento -Marco -AlertasEnviados`
- `ConvertTo-ItemNormalizado` (valida Tipo, Alvo, ContatosAlerta; separa e-mails por `;`).
**Aceite:** testes Pester cobrindo todos os exemplos da "Regra de marcos", fronteiras (31/30/16/15/8/7/1/0/-1/-7/-8), virada de fuso (23:30 BRT = dia seguinte em UTC), renovação (data nova → alerta pendente de novo). `Invoke-Pester` verde; `Invoke-ScriptAnalyzer` sem erros.

### T03 — Verificação de SSL
**Função:** `Get-CertificadoSsl -Host -Porta 443 -TimeoutMs 10000` → `NotAfter`, `Emissor`, `Assunto`, `Thumbprint`, `CadeiaValida`, `ErrosCadeia`, `Erro`.
**Detalhes:** `TcpClient` + `SslStream`, SNI com o host, callback de validação que **sempre aceita** (para conseguir ler certificados já vencidos ou inválidos) e registra os erros de cadeia; timeout de conexão; sempre dar `Dispose`.
**Aceite:** testes unitários com parsing de `Alvo` (`host`, `host:porta`, URL com `https://`); testes de integração com tag `Integration` contra `expired.badssl.com`, `self-signed.badssl.com` e `google.com` (excluídos do CI por padrão).

### T04 — Verificação de domínio (RDAP) — pode rodar em paralelo com T03
**Função:** `Get-VencimentoDominio -Dominio` → `DataExpiracao`, `Status`, `Fonte`, `Erro`.
**Detalhes:** `.br` → `https://rdap.registro.br/domain/<d>`; outros → `https://rdap.org/domain/<d>`; pegar `events[] | eventAction == 'expiration'`; tratar 404 (domínio não existe), 429 (rate limit — 1 nova tentativa com espera), timeout. Normalizar entrada (remover `www.`, esquema, caminho).
**Aceite:** fixtures JSON reais salvas em `tests/fixtures/rdap/` (um `.br`, um `.com`, um 404); testes mockando `Invoke-RestMethod`; teste de integração com tag `Integration` (`registro.br`).

### T05 — Camada de acesso ao Table Storage
**Arquivo:** `src/modules/Vencimentos/Storage.ps1` (ou módulo próprio).
**Funções:** `Get-TokenAcesso -Recurso` (Managed Identity via `IDENTITY_ENDPOINT`/`IDENTITY_HEADER`, com cache até expirar), `New-CabecalhoTabela` (Bearer **ou** SharedKeyLite para Azurite, conforme configuração), `Get-Entidades -Tabela -Filtro` (com paginação por `x-ms-continuation-*`), `Set-Entidade` (upsert — `InsertOrReplace`), `Remove-Entidade`, `New-TabelaSeNaoExistir`.
**Configuração por variáveis de ambiente:** `TABELAS_ENDPOINT`, `TABELAS_MODO_AUTH` (`ManagedIdentity`|`SharedKey`), `TABELAS_CONTA`, `TABELAS_CHAVE` (só local).
**Aceite:** testes unitários com mocks (cabeçalhos, escape de OData em filtros, paginação); script `tests/Integration/Storage.Tests.ps1` que roda contra Azurite local e faz CRUD completo.

### T06 — Envio de e-mail (ACS)
**Funções:** `Send-EmailAcs -Para -Assunto -Html -Texto` (REST `POST {endpoint}/emails:send?api-version=2023-03-31`, token do recurso `https://communication.azure.com`, acompanhar `Operation-Location` até `Succeeded`), `New-EmailAlerta -Contato -Itens` (monta HTML + texto puro, agrupado por urgência: vencidos → 0 → 7 → 15 → 30), `New-EmailResumoAdmin`.
**Modo local:** `EMAIL_MODO=Arquivo` grava o `.html` em `./saida-emails/` em vez de enviar.
**Aceite:** testes do template (itens ordenados, datas em `dd/MM/yyyy`, escape HTML de campos do usuário); testes do envio com mock; e-mail renderizado revisado visualmente.

### T07 — Orquestrador da verificação diária
**Função:** `Invoke-VerificacaoDiaria -Hoje` (em `src/modules`; a Function só chama ela).
**Fluxo:** ler `Itens` com `Ativo eq true` → para cada item despachar por `Tipo` (`SSL` → T03; `Dominio` → T04; `CertA3`/`Manual` → usar `DataVencimento` cadastrada; `CertA1` → última data recebida do agente, Fase 2) → gravar em `Verificacoes` (PK = `ItemId`, RK = data `yyyyMMdd`) → atualizar `DataVencimento` do item se for automática → calcular marco → agrupar por contato → enviar → gravar `AlertasEnviados` **só após envio bem-sucedido** → e-mail de resumo ao admin (`ADMIN_EMAIL`) com totais, alertas enviados e falhas.
**Regras:** erro em um item nunca interrompe os demais; execução idempotente (rodar 2× no mesmo dia não duplica alertas); limpeza de `Verificacoes` com mais de 12 meses.
**Aceite:** testes de ponta a ponta com todas as dependências mockadas: cenário feliz, item com falha, reexecução no mesmo dia, renovação, item vencido na semana 1 e 2, contato com vários itens (um e-mail só).

### T08 — Function App + execução local + importação de inventário
**Entrega:** `src/functions/host.json`, `profile.ps1` (importa o módulo), `requirements.psd1` vazio / managed dependencies desligado, `VerificacaoDiaria/function.json` (timer D6) + `run.ps1`, `local.settings.json.example`; `tools/Import-Itens.ps1` (lê CSV com colunas da tabela `Itens`, valida com `ConvertTo-ItemNormalizado`, faz upsert) + `tools/itens-exemplo.csv`; `tools/Start-Local.ps1` (sobe Azurite, cria tabelas, importa exemplo).
**Aceite:** `func start` localmente executa a verificação (usar `runOnStartup` só no local, via configuração) com Azurite, e gera e-mails em `saida-emails/`. Passo a passo documentado no README.

### T09 — Terraform do ambiente `dev`
**Entrega:**
- `infra/bootstrap/` — RG + Storage para o state do Terraform + App Registration/identidade com **federated credential** do GitHub (OIDC) e papéis mínimos. Executado uma vez manualmente.
- `infra/` — RG, Storage Account (sem acesso por chave compartilhada no prod: `shared_access_key_enabled = false`), tabelas `Itens`, `Verificacoes`, `AlertasEnviados`, `Clientes`, container de deploy do Flex; Function App Flex Consumption (PowerShell 7.4, identidade atribuída pelo sistema); Log Analytics + Application Insights com **limite diário de ingestão**; Key Vault (RBAC); ACS + Email Communication Service + domínio gerenciado pelo Azure (`dev`) + associação; atribuições de papel (Storage Table Data Contributor, Storage Blob Data Owner para o deploy, papel de envio no ACS, Key Vault Secrets User); Budget do RG; alerta do Azure Monitor para falha da função.
- `environments/dev.tfvars` e `prod.tfvars`.
**Antes de codar:** confirmar disponibilidade do Flex Consumption + PowerShell 7.4 na região (D5) e o papel de menor privilégio para envio via ACS com Entra ID.
**Aceite:** `terraform fmt -check` e `terraform validate` ok; `terraform plan` limpo com `dev.tfvars`. **[HUMANO]** rodar `bootstrap` e o primeiro `apply`.

### T10 — CI/CD (GitHub Actions)
**Entrega:** `.github/workflows/ci.yml` (PR e push: PSScriptAnalyzer, Pester sem tag `Integration`, `terraform fmt/validate`) e `deploy.yml` (push na `main` ou manual: `azure/login` via OIDC → `terraform apply` → zip de `src/functions` + módulos → `Azure/functions-action`).
**Aceite:** CI verde em um PR de teste. **[HUMANO]** configurar variáveis do repositório (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`) e o environment `dev` com aprovação manual.

### T11 — Documentação e LGPD
**Entrega:** `README.md` completo (o que faz / o que **não** faz — nunca chave privada, `.pfx` ou senha), `docs/privacidade.md` (dados coletados, finalidade, retenção de 12 meses, local de armazenamento), `docs/runbook.md` (como cadastrar itens, reprocessar um dia, trocar contato, investigar falha no App Insights, rotacionar configurações).
**Aceite:** alguém que não conhece o projeto consegue subir localmente e cadastrar um item só lendo o README.

### T12 — Deploy em dev e teste real [HUMANO + Sonnet]
- [ ] Deploy via pipeline; cadastrar seus próprios itens (seu domínio, seu site, um A3 com data fictícia próxima).
- [ ] Ajustar datas para disparar cada marco e conferir recebimento, entrega fora do spam e deduplicação.
- [ ] Deixar rodando 7 dias e conferir o resumo diário do admin.

### Piloto (30 dias) [HUMANO]
- [ ] 2–3 clientes com permissão por escrito; montar o CSV de cada um; definir destinatários.
- [ ] Ambiente `prod` (mesmo Terraform com `prod.tfvars`) + domínio próprio no ACS com SPF, DKIM e DMARC.
- [ ] Coletar feedback: utilidade dos marcos, clareza do e-mail, itens que faltaram.

---

## Fase 2 — Agente A1 (detalhar após o piloto)

- **T20** Especificação da API `ReceberAgente` (contrato JSON, versionamento, limites de tamanho) + ADR.
- **T21** Function HTTP `ReceberAgente`: valida chave de API (hash na tabela `Clientes`, comparação em tempo constante), valida payload, upsert em `Itens` com `Tipo=CertA1`, RK = thumbprint.
- **T22** Agente `agent/Coletar-CertificadosA1.ps1` compatível com **PowerShell 5.1**: lê `Cert:\CurrentUser\My` e `Cert:\LocalMachine\My`, filtra emissores ICP-Brasil (lista configurável), envia só metadados; log local; nunca exporta chave privada.
- **T23** Instalador `agent/Instalar-Agente.ps1` (tarefa agendada diária + no logon, para pegar o repositório do usuário) e desinstalador.
- **T24** Tratamento de A1 que sumiu da máquina (renovado ou removido) e testes.
- **[HUMANO]** Levantar a lista de ACs ICP-Brasil usadas pelos clientes do piloto e as versões de Windows.

## Fase 3 — Produto (detalhar após a Fase 2)

Multi-tenant por `ClienteId` com validação em toda a API → portal em Static Web Apps (auth Entra External ID) → canais Teams/WhatsApp → relatório mensal → cobrança e planos. Pré-requisitos **[HUMANO]**: forma jurídica (contador), termos de uso e política de privacidade, nome (INPI + domínio), meio de cobrança, pesquisa de preço com 3–5 clientes.

---

## Ordem e dependências

```
M0 → T01 → T02 → T03 ┐
                T04 ┘→ T05 → T06 → T07 → T08 → T09 → T10 → T11 → T12 → Piloto → Fase 2
```

T11 pode ser escrito aos poucos a partir da T08.
