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
| D9 | Item vencido | Marco `0` no dia do vencimento; depois, alerta "VENCIDO" com **repetição a cada 7 dias** enquanto `Ativo=true` | Não deixar item vencido esquecido |
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
- [x] **M0.2** Assinatura Azure pessoal + **Budget com alerta** (ex.: US$ 10/mês, alertas a 50/80/100%). — Confirmado em 2026-09-22: assinatura "Azure subscription 1" (`id-da-assinatura`) já logada via `az`; budget `laboratorio-mensal-50-brl` (R$ 50/mês, alertas 50/80/100% para voce@exemplo.com) já existente e cobrindo a assinatura.
- [x] **M0.3** Conta GitHub e repositório **privado** `monitor-vencimentos` (vazio). — Criado em 2026-09-22: https://github.com/brunokdalcastel/monitor-vencimentos (privado); histórico local (T01+T02) enviado para `origin/master`.
- [x] **M0.4** Instalar localmente: PowerShell 7.4+, Azure Functions Core Tools v4, Azurite (`npm i -g azurite`), Terraform ≥ 1.9, Azure CLI, Git, Pester 5 e PSScriptAnalyzer (`Install-Module Pester, PSScriptAnalyzer -Scope CurrentUser`). — Confirmado em 2026-09-22: PowerShell 7.4.20, Git 2.52.0, Terraform 1.14.3, Azure CLI 2.80.0, Azure Functions Core Tools 4.15.0, Azurite 3.37.0, Pester 5.9.1, PSScriptAnalyzer 1.25.0. Pester/PSScriptAnalyzer instalados no módulo do Windows PowerShell 5.1; se necessário no 7.4, rodar `Install-Module` novamente dentro do `pwsh`.
- [ ] **M0.5** Revisar a tabela de decisões acima e ajustar o que quiser.
- [ ] **M0.6** (pode esperar até o prod) Domínio próprio para envio de e-mail.

---

## Fase 1 — MVP

### T01 — Estrutura do repositório ✅ Concluída (2026-09-22)
**Entrega:** `git init`, estrutura da seção 9 da especificação, `.gitignore` (PowerShell, Terraform, `local.settings.json`, `.azurite/`), `README.md` inicial, `docs/arquitetura.md` (copiar diagrama da especificação), ADRs `0001`…`0012` (um por decisão D1–D12, formato curto: contexto / decisão / consequências), mover a especificação para `docs/especificacao.md` (e atualizar o caminho no `CLAUDE.md`), `PSScriptAnalyzerSettings.psd1` na raiz.
**Aceite:** árvore de pastas criada; `git status` limpo após commit inicial; nenhum segredo versionado.
**Pendências:** nenhuma. O caminho da especificação no `CLAUDE.md` já apontava para `docs/especificacao.md`, então não precisou de alteração. `docs/privacidade.md` (previsto na estrutura da seção 9) será criado na T11, conforme o plano. Repositório remoto no GitHub (`monitor-vencimentos`, privado) é tarefa do Marco 0 [HUMANO] — este commit está só local até lá.

### T02 — Módulo de regras (lógica pura) + Pester ✅ Concluída (2026-09-22)
**Arquivo:** `src/modules/Vencimentos/Vencimentos.psm1` (+ `.psd1`).
**Funções:**
- `Get-DataHojeBrasil` → `[datetime]` só a data no fuso `America/Sao_Paulo` (aceita `-Agora` para teste).
- `Get-DiasRestantes -DataVencimento -Hoje`
- `Get-MarcoDevido -DiasRestantes` → `30|15|7|0|VENCIDO-n|$null`
- `Test-AlertaPendente -ItemId -DataVencimento -Marco -AlertasEnviados`
- `ConvertTo-ItemNormalizado` (valida Tipo, Alvo, ContatosAlerta; separa e-mails por `;`).
**Aceite:** testes Pester cobrindo todos os exemplos da "Regra de marcos", fronteiras (31/30/16/15/8/7/1/0/-1/-7/-8), virada de fuso (23:30 BRT = dia seguinte em UTC), renovação (data nova → alerta pendente de novo). `Invoke-Pester` verde; `Invoke-ScriptAnalyzer` sem erros.
**Pendências:** 70 testes em `tests/Vencimentos.Tests.ps1` passando (Pester 5.9.1) e ScriptAnalyzer sem apontamentos, validados no **Windows PowerShell 5.1** e no **PowerShell 7.4.20** (Windows; o Linux das Functions será coberto pelo CI na T10). No 7.4 o fuso é resolvido como `America/Sao_Paulo`; no 5.1 (.NET Framework) cai no fallback `E. South America Standard Time`. Duas escolhas além do texto da tarefa: `ConvertTo-ItemNormalizado` também exige `DataVencimento` (`yyyy-MM-dd`) para `CertA3`/`Manual` e normaliza `Ativo`. `Test-AlertaPendente` espera registros com `ItemId`, `DataVencimento` e `Marco`; o formato de PK/RK de `AlertasEnviados` fica para a T05/T07. ADR 0009 alinhado à Regra de marcos (marco `0` no dia do vencimento, `VENCIDO-n` a partir de −1).

### T03 — Verificação de SSL ✅ Concluída (2026-09-22)
**Função:** `Get-CertificadoSsl -Host -Porta 443 -TimeoutMs 10000` → `NotAfter`, `Emissor`, `Assunto`, `Thumbprint`, `CadeiaValida`, `ErrosCadeia`, `Erro`.
**Detalhes:** `TcpClient` + `SslStream`, SNI com o host, callback de validação que **sempre aceita** (para conseguir ler certificados já vencidos ou inválidos) e registra os erros de cadeia; timeout de conexão; sempre dar `Dispose`.
**Aceite:** testes unitários com parsing de `Alvo` (`host`, `host:porta`, URL com `https://`); testes de integração com tag `Integration` contra `expired.badssl.com`, `self-signed.badssl.com` e `google.com` (excluídos do CI por padrão).
**Pendências:** implementado em `src/modules/Ssl/Ssl.psm1` (+ `.psd1`), com uma função extra não nomeada no texto da tarefa: `ConvertTo-EnderecoSsl -Alvo -PortaPadrao` (separa host/porta a partir do `Alvo` cadastrado — é ela quem tem os testes unitários de parsing; `Get-CertificadoSsl` só tem testes de integração, por depender de socket/TLS real). A cadeia de confiança é construída localmente com `RevocationMode = NoCheck` (não usa o objeto de cadeia que o .NET passa por padrão no callback) para o resultado não depender de CRL/OCSP externos — decisão de implementação, não uma das D1–D12. 88 testes no total (70 da T02 + 18 da T03) verdes em Windows PowerShell 5.1 e PowerShell 7.4.20, incluindo os 4 de integração rodados de verdade contra a rede (não só simulados). `ScriptAnalyzer` sem apontamentos. Faltou testar o parsing de IPv6 em `Alvo` (não estava no aceite; ficaria ambíguo com o separador `:` de porta — avaliar na T07 se surgir a necessidade).

### T04 — Verificação de domínio (RDAP) — pode rodar em paralelo com T03 ✅ Concluída (2026-09-23)
**Função:** `Get-VencimentoDominio -Dominio` → `DataExpiracao`, `Status`, `Fonte`, `Erro`.
**Detalhes:** `.br` → `https://rdap.registro.br/domain/<d>`; outros → `https://rdap.org/domain/<d>`; pegar `events[] | eventAction == 'expiration'`; tratar 404 (domínio não existe), 429 (rate limit — 1 nova tentativa com espera), timeout. Normalizar entrada (remover `www.`, esquema, caminho).
**Aceite:** fixtures JSON reais salvas em `tests/fixtures/rdap/` (um `.br`, um `.com`, um 404); testes mockando `Invoke-RestMethod`; teste de integração com tag `Integration` (`registro.br`).
**Pendências:** implementado em `src/modules/Dominio/Dominio.psm1` (+ `.psd1`), seguindo o padrão da T03: `ConvertTo-DominioNormalizado` (remove esquema, `www.`, caminho/query, minúsculas — só ela tem testes unitários de parsing) e `Get-VencimentoDominio` (consulta RDAP real via `Invoke-RestMethod`, sem lançar exceção — falhas voltam em `Status`/`Erro`). `Status` devolve `'Ok'|'NaoEncontrado'|'Erro'` (não o array de status RDAP do domínio, que não é usado pela regra de marcos). Fixtures reais em `tests/fixtures/rdap/`: `registro-br-globo.com.br.json` (`.br`, com evento `expiration`), `rdap-org-google.com.json` (`.com` via bootstrap), `rdap-org-404-not-found.json` (404 real do RDAP da PIR/.org). O domínio `registro.br` (citado no aceite) não tem evento `expiration` na resposta RDAP (é o domínio reservado do próprio NIC.br) — o teste de integração usa `globo.com.br` para o caminho `.br` e `dominioinexistentexyz123456789.br` para o caso `NaoEncontrado`; ambos batem no mesmo serviço `rdap.registro.br`. Retentativa de 429: detecta o código HTTP tanto por `Exception.Response.StatusCode` (chamada real, WebException no 5.1 / HttpResponseException no 7.x) quanto por regex na mensagem (mocks de teste); espera configurável via `-EsperaRetentativaMs` (padrão 2000ms, testes usam 0). 109 testes no total (88 da T02+T03 + 21 novos em `Dominio.Tests.ps1`: 18 unitários + 3 de integração real contra `rdap.registro.br` e `rdap.org`) verdes em Windows PowerShell 5.1 e PowerShell 7.4; `ScriptAnalyzer` sem apontamentos (BOM UTF-8 adicionado aos novos arquivos para bater com o padrão dos módulos anteriores).

### T05 — Camada de acesso ao Table Storage ✅ Concluída (2026-09-24)
**Arquivo:** `src/modules/Vencimentos/Storage.ps1` (ou módulo próprio).
**Funções:** `Get-TokenAcesso -Recurso` (Managed Identity via `IDENTITY_ENDPOINT`/`IDENTITY_HEADER`, com cache até expirar), `New-CabecalhoTabela` (Bearer **ou** SharedKeyLite para Azurite, conforme configuração), `Get-Entidades -Tabela -Filtro` (com paginação por `x-ms-continuation-*`), `Set-Entidade` (upsert — `InsertOrReplace`), `Remove-Entidade`, `New-TabelaSeNaoExistir`.
**Configuração por variáveis de ambiente:** `TABELAS_ENDPOINT`, `TABELAS_MODO_AUTH` (`ManagedIdentity`|`SharedKey`), `TABELAS_CONTA`, `TABELAS_CHAVE` (só local).
**Aceite:** testes unitários com mocks (cabeçalhos, escape de OData em filtros, paginação); script `tests/Integration/Storage.Tests.ps1` que roda contra Azurite local e faz CRUD completo.
**Pendências:** implementado em dois módulos — `src/modules/Identidade/Identidade.psm1` (`Get-TokenAcesso`, reaproveitável pela T06 com o recurso ACS) e `src/modules/Storage/Storage.psm1` (as demais 5 funções, que importam o módulo Identidade). Divisão não pedida literalmente pelo texto da tarefa (que sugeria um único `Storage.ps1`), mas evita duplicar a lógica de Managed Identity na T06 — decisão de organização, não uma das D1–D12. Achados de implementação relevantes, todos verificados contra o Azurite 3.37 real (não só mockado):
- **Canonicalização SharedKeyLite no Azurite:** como a URL do Azurite é path-style (conta no caminho: `http://127.0.0.1:10002/devstoreaccount1/Tabela`), o recurso canonicalizado que o Azurite espera repete a conta (`/devstoreaccount1/devstoreaccount1/Tabela`), diferente da doc genérica do Shared Key (que assume conta só no host, ambiente de produção real). Confirmado lendo o código-fonte do Azurite e validado com todas as operações. Só afeta o modo `SharedKey` (uso exclusivamente local, ver ADR 0003); `ManagedIdentity` usa Bearer token e não tem esse problema.
- **`-UseBasicParsing` é obrigatório em `Invoke-WebRequest`** para POST/PUT/DELETE funcionarem no Windows PowerShell 5.1: sem essa flag, o cmdlet tenta usar o engine do Internet Explorer e falha com `"Object reference not set to an instance of an object"` (ou trava) nesta máquina.
- **Retorno de array de 1 item quebra em PS 5.1:** `Get-Entidades` usa `return , $entidades.ToArray()` (vírgula unária) — sem ela, o `return` "desembrulha" um array de 1 elemento em escalar ao atravessar o pipeline; no PowerShell 7.x isso passa despercebido porque todo objeto ganhou `.Count`/`.Length` desde a 7.0, mas quebra de verdade no Windows PowerShell 5.1 (`.Count` de um objeto escalar é `$null`). Achado pelo teste de integração real rodando nas duas versões — os testes unitários (mockados) não pegaram, porque só testavam 0 ou 2+ itens.
- `Status` do `New-TabelaSeNaoExistir` engole especificamente 409 (`TableAlreadyExists`) e propaga qualquer outro erro.
- `New-CabecalhoTabela`, `New-TabelaSeNaoExistir`, `Set-Entidade`, `Remove-Entidade` e `Get-Entidades` têm nome fixado pelo texto da tarefa; supressões do ScriptAnalyzer (`PSUseShouldProcessForStateChangingFunctions` em `New-CabecalhoTabela`, que não muda estado; `PSUseSingularNouns` em `Get-Entidades`, que devolve várias entidades por natureza) documentadas no próprio código. `New-TabelaSeNaoExistir`, `Set-Entidade` e `Remove-Entidade` implementam `SupportsShouldProcess` de verdade (idiomático para verbos que mudam estado; não muda o comportamento para quem já chama sem `-WhatIf`/`-Confirm`).
- 144 testes no total (109 da T02–T04 + 6 em `Identidade.Tests.ps1` + 23 em `Storage.Tests.ps1` + 6 em `tests/Integration/Storage.Tests.ps1`) verdes em Windows PowerShell 5.1 e PowerShell 7.4, unitários e de integração real contra o Azurite; `ScriptAnalyzer` sem apontamentos.
- Versão da API de tabelas usada: `2020-12-06` (compatível com o Azurite 3.37 instalado no M0.4).

### T06 — Envio de e-mail (ACS) ✅ Concluída (2026-09-24)
**Funções:** `Send-EmailAcs -Para -Assunto -Html -Texto` (REST `POST {endpoint}/emails:send?api-version=2023-03-31`, token do recurso `https://communication.azure.com`, acompanhar `Operation-Location` até `Succeeded`), `New-EmailAlerta -Contato -Itens` (monta HTML + texto puro, agrupado por urgência: vencidos → 0 → 7 → 15 → 30), `New-EmailResumoAdmin`.
**Modo local:** `EMAIL_MODO=Arquivo` grava o `.html` em `./saida-emails/` em vez de enviar.
**Aceite:** testes do template (itens ordenados, datas em `dd/MM/yyyy`, escape HTML de campos do usuário); testes do envio com mock; e-mail renderizado revisado visualmente.
**Pendências:** implementado em `src/modules/Email/Email.psm1` (+ `.psd1`), reaproveitando `Get-TokenAcesso` do módulo Identidade (T05) para o recurso `https://communication.azure.com`. Como ainda não existe recurso ACS real (infra só na T09), não há teste de integração contra o Azure de verdade nesta tarefa — `Send-EmailAcs` é testado 100% com mocks (envio, `Operation-Location` em `Running`→`Succeeded`, `Failed`, timeout, cabeçalho ausente); o modo `EMAIL_MODO=Arquivo` já é testado de verdade (escreve arquivo em disco). E-mails de exemplo gerados em modo Arquivo e revisados visualmente no Chrome (servidos por um HTTP estático local, já que a extensão não abre `file://`) — tabelas, agrupamento por urgência e escape de HTML (`<script>`, `<img onerror>`, aspas) todos corretos.
- Decisões de variáveis de ambiente não detalhadas no texto da tarefa (`ADR` não exigido — não contraria D1–D12, é só configuração): `ACS_ENDPOINT` (base do recurso ACS), `ACS_REMETENTE` (endereço remetente verificado), `EMAIL_SAIDA_DIR` (override opcional do diretório do modo Arquivo, padrão `./saida-emails`).
- `New-EmailResumoAdmin` não tinha assinatura exata no PLANO.md — implementada como `-Data -TotalItensVerificados -AlertasEnviados -Falhas` (`AlertasEnviados`: objetos com `Contato`/`TotalItens`; `Falhas`: objetos com `Tipo`/`Alvo`/`Erro`). A T07 (orquestrador) é quem efetivamente vai montar essas listas; o contrato pode precisar de ajuste fino quando ela for implementada.
- `ConvertTo-TextoHtmlSeguro` (escapa com `System.Net.WebUtility.HtmlEncode`, cross-version sem dependência de `System.Web`) é usada em todo campo de cadastro que entra no HTML: `Alvo` dos itens, `Contato` no rodapé do alerta, `Alvo`/`Erro`/`Tipo` das falhas no resumo do admin.
- 173 testes no total (152 da T02–T05 + 21 em `Email.Tests.ps1`, todos unitários/mockados) verdes em Windows PowerShell 5.1 e PowerShell 7.4; `ScriptAnalyzer` sem apontamentos (supressões documentadas no código: `New-EmailAlerta`/`New-EmailResumoAdmin` não mudam estado, `Send-EmailAcs` não é plural — nomes fixados pelo PLANO.md).

### T07 — Orquestrador da verificação diária ✅ Concluída (2026-09-24)
**Função:** `Invoke-VerificacaoDiaria -Hoje` (em `src/modules`; a Function só chama ela).
**Fluxo:** ler `Itens` com `Ativo eq true` → para cada item despachar por `Tipo` (`SSL` → T03; `Dominio` → T04; `CertA3`/`Manual` → usar `DataVencimento` cadastrada; `CertA1` → última data recebida do agente, Fase 2) → gravar em `Verificacoes` (PK = `ItemId`, RK = data `yyyyMMdd`) → atualizar `DataVencimento` do item se for automática → calcular marco → agrupar por contato → enviar → gravar `AlertasEnviados` **só após envio bem-sucedido** → e-mail de resumo ao admin (`ADMIN_EMAIL`) com totais, alertas enviados e falhas.
**Regras:** erro em um item nunca interrompe os demais; execução idempotente (rodar 2× no mesmo dia não duplica alertas); limpeza de `Verificacoes` com mais de 12 meses.
**Aceite:** testes de ponta a ponta com todas as dependências mockadas: cenário feliz, item com falha, reexecução no mesmo dia, renovação, item vencido na semana 1 e 2, contato com vários itens (um e-mail só).
**Pendências:** implementado em `src/modules/Orquestrador/Orquestrador.psm1` (+ `.psd1`), importando os módulos Vencimentos/Ssl/Dominio/Storage/Email. Decisões que a T02/T05 deixaram em aberto e foram resolvidas aqui (nenhuma contraria D1–D12, são detalhes de implementação):
- **PK/RK de `Verificacoes`**: exatamente como no texto da tarefa (PK=`ItemId`, RK=`yyyyMMdd`).
- **PK/RK de `AlertasEnviados`**: PK=`ItemId`, RK=`{DataVencimento:yyyyMMdd}-{Marco}`, com `ItemId`/`DataVencimento`/`Marco`/`DataEnvio` também como colunas explícitas (não só embutidos na RK) — é isso que o `Test-AlertaPendente` do módulo Vencimentos (T02) espera receber.
- **Entidade bruta da tabela `Itens` não repete `ClienteId`/`ItemId` como colunas** (só existem como PartitionKey/RowKey, conforme `docs/especificacao.md`) — `ConvertTo-ItemDoStorage` preenche esses dois campos a partir de PartitionKey/RowKey antes de chamar `ConvertTo-ItemNormalizado` (T02).
- **Falha parcial de envio (item com 2+ contatos, um falha)**: só grava `AlertasEnviados` para o item quando *todos* os contatos receberam com sucesso; falha parcial refaz a tentativa inteira no dia seguinte (o marco continua pendente) — decisão registrada no código, já que o ADR 0008 não cobre esse caso.
- **"Após 3 falhas seguidas, avisa o admin explicitamente" (regra de marcos)**: implementado contando falhas consecutivas de `Verificacoes` (via `Get-ContagemFalhasConsecutivas`) e anexando um aviso("ATENÇÃO: N verificações seguidas falharam") na mensagem de erro que já vai no resumo do admin — não criei um tipo de e-mail separado pra isso.
- **`CertA1` sem `DataVencimento`** (Fase 2/agente ainda não existe): item é pulado silenciosamente (não conta como falha, não gera `Verificacoes`), já que não há nada pra verificar ainda.
- **Datas de SSL/Dominio**: uso a data (UTC) devolvida por `Get-CertificadoSsl`/`Get-VencimentoDominio` diretamente (`.Date`), sem converter para o fuso de São Paulo — consistente com T03/T04, que já devolvem essas datas em UTC.
- Testado também de ponta a ponta contra o Azurite real (não só mockado): 2 itens ativos + 1 inativo (corretamente ignorado), um `Manual` com marco `7` e um `SSL` real contra `expired.badssl.com` (vencido desde 2015, virou `VENCIDO-597`), e-mails gerados em modo Arquivo revisados, segunda execução no mesmo dia não duplicou nada.
- 186 testes no total (169 da T02–T06 + 17 novos em `Orquestrador.Tests.ps1`, todos com as dependências de rede/Storage/e-mail mockadas — a lógica pura do módulo Vencimentos roda de verdade nos testes, sem mock, por ser determinística) verdes em Windows PowerShell 5.1 e PowerShell 7.4; `ScriptAnalyzer` sem apontamentos.

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

> **Premissa (confirmada em 2026-09-22):** não teremos acesso remoto às máquinas dos clientes onde o certificado A1 está instalado. Por isso o agente precisa ser autoinstalável — o cliente (ou o TI dele) executa o instalador (T23) uma vez, e daí em diante só há tráfego de saída da máquina dele para a API (T21). Nenhuma tarefa desta fase pode assumir acesso direto/remoto a essas máquinas.

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
