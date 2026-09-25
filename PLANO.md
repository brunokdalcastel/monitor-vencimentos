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
| D1 | Envio de e-mail | **ACS Email**, autenticado por **Managed Identity** via REST | Sem segredo; domínio gerenciado pelo Azure no `dev` — sem custo, sem comprar domínio (só valeria domínio próprio se houvesse `prod`/piloto, fora de escopo por ora, ver ADR 0013) |
| D2 | Acesso ao Table Storage | **Wrapper REST próprio** (`Invoke-RestMethod`) — sem módulos Az/AzTable | Flex Consumption **não suporta managed dependencies**; zero dependências = pacote simples e testável |
| D3 | Autenticação | Prod: token da Managed Identity (`IDENTITY_ENDPOINT`). Local: **SharedKey** contra Azurite | Mesmo código nos dois ambientes |
| D4 | Plano da Function | **Flex Consumption**, PowerShell **7.6** (revisado, ver [ADR 0014](docs/decisoes/0014-powershell-76-no-flex.md); era 7.4), Linux | Cota gratuita, identidade em tudo. 7.4 no Flex vence em 10/nov/2026. Fallback: Consumption (Windows) |
| D5 | Região | **Brazil South** (validar disponibilidade do Flex na T09; fallback East US 2) | Dados no Brasil é argumento de venda |
| D6 | Horário | Timer `0 0 11 * * *` (UTC) = **08:00 BRT**; cálculo de dias no fuso `America/Sao_Paulo` | Flex/Linux não aceita `WEBSITE_TIME_ZONE` |
| D7 | Alertas | **Um e-mail consolidado por contato por dia** (não um por item) | Menos ruído, menos custo |
| D8 | Deduplicação | Chave de `AlertasEnviados` = `ItemId` + `DataVencimento` + `Marco` | Renovou → data muda → ciclo de alertas reinicia sozinho |
| D9 | Item vencido | Marco `0` no dia do vencimento; depois, alerta "VENCIDO" com **repetição a cada 7 dias** enquanto `Ativo=true` | Não deixar item vencido esquecido |
| D10 | Cadastro de A3/Manual no MVP | **CSV + script** `tools/Import-Itens.ps1` | Portal só na Fase 3 |
| D11 | IaC / CI | Terraform (azurerm 4.x) com state em Storage separado; GitHub Actions com OIDC | Conforme especificação |
| D12 | Domínios não-.br | RDAP via bootstrap IANA (`https://rdap.org/domain/<d>`); `.br` direto no Registro.br | Cobre clientes com `.com` |
| D13 | Escopo do projeto | Uso **pessoal/portfólio**, sem piloto pago nem domínio próprio (ver [ADR 0013](docs/decisoes/0013-escopo-pessoal-sem-piloto.md)) | Usuário não vai comprar domínio nem buscar clientes reais; infra fica de pé sob demanda, custo ~zero parada |
| D14 | Versão do PowerShell na Function | **7.6**, não 7.4 (ver [ADR 0014](docs/decisoes/0014-powershell-76-no-flex.md)) | 7.4 no Flex Consumption vence em 10/nov/2026 (checado antes de codar a T09) |

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
- [x] **M0.2** Assinatura Azure pessoal + **Budget com alerta** (ex.: US$ 10/mês, alertas a 50/80/100%). — Confirmado em 2026-09-22: assinatura pessoal já logada via `az`; budget de assinatura (R$ 50/mês, alertas 50/80/100% para o e-mail do dono) já existente e cobrindo a assinatura.
- [x] **M0.3** Conta GitHub e repositório **privado** `monitor-vencimentos` (vazio). — Criado em 2026-09-22: https://github.com/brunokdalcastel/monitor-vencimentos — tornado **público** em 2026-09-25 para portfólio, após reescrever o histórico removendo dados pessoais (e-mail em arquivos e no autor dos commits → noreply do GitHub; ID da assinatura).
- [x] **M0.4** Instalar localmente: PowerShell 7.4+, Azure Functions Core Tools v4, Azurite (`npm i -g azurite`), Terraform ≥ 1.9, Azure CLI, Git, Pester 5 e PSScriptAnalyzer (`Install-Module Pester, PSScriptAnalyzer -Scope CurrentUser`). — Confirmado em 2026-09-22: PowerShell 7.4.20, Git 2.52.0, Terraform 1.14.3, Azure CLI 2.80.0, Azure Functions Core Tools 4.15.0, Azurite 3.37.0, Pester 5.9.1, PSScriptAnalyzer 1.25.0. Pester/PSScriptAnalyzer instalados no módulo do Windows PowerShell 5.1; se necessário no 7.4, rodar `Install-Module` novamente dentro do `pwsh`.
- [ ] **M0.5** Revisar a tabela de decisões acima e ajustar o que quiser.
- [x] **M0.6** ~~Domínio próprio para envio de e-mail~~ — fora de escopo (ver ADR 0013, 2026-09-25): `dev` usa o domínio gerenciado pelo Azure no ACS, sem custo.

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

### T08 — Function App + execução local + importação de inventário ✅ Concluída (2026-09-24)
**Entrega:** `src/functions/host.json`, `profile.ps1` (importa o módulo), `requirements.psd1` vazio / managed dependencies desligado, `VerificacaoDiaria/function.json` (timer D6) + `run.ps1`, `local.settings.json.example`; `tools/Import-Itens.ps1` (lê CSV com colunas da tabela `Itens`, valida com `ConvertTo-ItemNormalizado`, faz upsert) + `tools/itens-exemplo.csv`; `tools/Start-Local.ps1` (sobe Azurite, cria tabelas, importa exemplo).
**Aceite:** `func start` localmente executa a verificação (usar `runOnStartup` só no local, via configuração) com Azurite, e gera e-mails em `saida-emails/`. Passo a passo documentado no README.
**Pendências:** testado de ponta a ponta de verdade com `func start` + Azurite + rede real (não só planejado) — achados que mudaram o desenho original em relação ao texto da tarefa:
- **`runOnStartup` não aceita `%AppSetting%`**: é lido como `Boolean` na hora de montar o `function.json`, e uma string tipo `"%VAR%"` não resolvida quebra o parse ("String '%...%' was not recognized as a valid Boolean") — confirmado rodando `func start` de verdade. Troquei a estratégia: `function.json` não define `runOnStartup` (sempre `false`, seguro em produção), e o "rodar agora" local vira `curl -X POST http://localhost:7071/admin/functions/VerificacaoDiaria` (API administrativa padrão do Functions runtime para disparar qualquer função manualmente) — documentado no README e no `Start-Local.ps1`. `%AppSetting%` funciona normalmente para o `schedule` (string), só não para `runOnStartup` (bool).
- **`AzureWebJobsStorage=UseDevelopmentStorage=true` não basta**: mesmo o projeto só acessando Storage via REST próprio (D2), o *host* do Functions precisa de blob/queue funcionando de verdade pro próprio `AzureWebJobsStorage` (lease do timer trigger, etc.) — sem isso o host fica `Unhealthy` (`azure.functions.webjobs.storage`) e a função nem carrega. `Start-Local.ps1` agora sobe o Azurite completo (blob+queue+table), com blob/queue em portas alternativas (11000/11001) para não conflitar com outra instância de Azurite que porventura já esteja rodando na máquina; `local.settings.json.example` tem a connection string completa (host/portas explícitos) em vez do atalho `UseDevelopmentStorage=true`.
- **Máquina sem .NET 8.0 instalado** (só 9/10): o worker PowerShell 7.4 do Core Tools 4.15.0 pede exatamente 8.0 e falha ("You must install or update .NET"). Contornado com `$env:DOTNET_ROLL_FORWARD='LatestMajor'` (não precisa instalar nada) — documentado no README como troubleshooting, já que é uma característica desta máquina, não do projeto.
- `Start-Process -FilePath 'azurite' ...` não iniciava de forma confiável no Windows (o `azurite` do npm é um `.cmd`); troquei para `Start-Process -FilePath 'cmd.exe' -ArgumentList '/c','azurite',...`, mais robusto.
- Achei e corrigi um bug de verdade em `tools/itens-exemplo.csv`: uma vírgula não escapada dentro do campo `Descricao` da primeira linha deslocava as colunas seguintes (`ContatosAlerta`/`Ativo`) — `ConvertTo-ItemNormalizado` pegou certinho e reportou o erro sem derrubar a importação dos outros itens, confirmando na prática a regra "erro numa linha não interrompe as demais" do `Import-Itens.ps1`.
- Rodei o fluxo completo de verdade: `Start-Local.ps1` → `func start --script-root src/functions` → `POST /admin/functions/VerificacaoDiaria` → 4 itens verificados (SSL real contra `www.google.com`, RDAP real contra `google.com`, `CertA3` e `Manual` com data cadastrada) → 2 alertas + 1 resumo ao admin gerados em `saida-emails/` → reexecução no mesmo dia corretamente sem duplicar (0 novos alertas, só o resumo do admin de novo).
- `PSMissingModuleManifestField` no `requirements.psd1`: falso positivo conhecido do ScriptAnalyzer (confunde o arquivo de dependências do worker do Functions com um manifesto de módulo real) — não suprimível por comentário nem atributo sem quebrar o arquivo (precisa continuar sendo só uma hashtable pura, sem `param()`); é o único apontamento que sobra no `Invoke-ScriptAnalyzer -Path ./src`, documentado aqui.

### T09 — Terraform do ambiente `dev` ✅ Concluída (2026-09-25)
**Entrega:**
- `infra/bootstrap/` — RG + Storage para o state do Terraform + App Registration/identidade com **federated credential** do GitHub (OIDC) e papéis mínimos. Executado uma vez manualmente.
- `infra/` — RG, Storage Account (sem acesso por chave compartilhada: `shared_access_key_enabled = false` — a Function usa Managed Identity mesmo em `dev`, ver D3), tabelas `Itens`, `Verificacoes`, `AlertasEnviados`, `Clientes`, container de deploy do Flex; Function App Flex Consumption (PowerShell 7.4, identidade atribuída pelo sistema); Log Analytics + Application Insights com **limite diário de ingestão** (mantém dentro do tier sempre gratuito de 5GB/mês); Key Vault (RBAC); ACS + Email Communication Service + domínio gerenciado pelo Azure (sem custo, sem comprar domínio — ver ADR 0013); atribuições de papel (Storage Table Data Contributor, Storage Blob Data Owner para o deploy, papel de envio no ACS, Key Vault Secrets User); Budget do RG; alerta do Azure Monitor para falha da função.
- `environments/dev.tfvars` (só `dev` — ver ADR 0013: sem plano de `prod`/piloto por enquanto).
**Antes de codar:** confirmar disponibilidade do Flex Consumption + PowerShell 7.4 na região (D5) e o papel de menor privilégio para envio via ACS com Entra ID.
**Aceite:** `terraform fmt -check` e `terraform validate` ok; `terraform plan` limpo com `dev.tfvars`. **[HUMANO]** rodar `bootstrap` e o primeiro `apply`.
**Pendências:**
- **PowerShell 7.4 → 7.6** (ver D14/ADR 0014): checando a disponibilidade antes de codar, achei que o Flex Consumption só suporta 7.4 até 10/nov/2026 — troquei para 7.6 (padrão atual, suporte até 2028), aprovado com o usuário.
- **`infra/bootstrap/` cria o RG de `dev` vazio** (não a `infra/` principal, que só referencia via `data "azurerm_resource_group"`) — de propósito, pra dar `Contributor` + `Role Based Access Control Administrator` pro GitHub Actions só nesse RG, nunca na assinatura inteira. `Role Based Access Control Administrator` (não `User Access Administrator`) porque não permite a identidade se autoelevar.
- **Backend do state sem chave**: `use_azuread_auth = true` no `backend.tf` — nem a autenticação da automação usa `shared_access_key_enabled`, consistente com D3 em tudo, não só no workload.
- Convenção de nomes: prefixo `mvenc` (monitor-vencimentos) — nomes de Storage Account/Key Vault levam um sufixo aleatório (`random_string`) porque precisam ser globalmente únicos.

**Bootstrap e `apply` rodados de verdade em 2026-09-25** (eu executei, com autorização explícita do usuário — ver conversa) — 6 problemas reais encontrados e corrigidos, nenhum previsível só lendo documentação, só rodando contra a API de verdade:

1. **`storage_use_azuread` faltando no provider**: sem esse argumento no bloco `provider "azurerm"`, a checagem interna do provider de "a Storage Account está disponível" (roda logo após criar o recurso) usa autenticação por **chave** por padrão — e falha com 403 porque `shared_access_key_enabled = false` (D3). Corrigido nos dois diretórios (`bootstrap/` e principal). A Storage Account do state chegou a ficar `tainted` por causa disso — resolvido com `terraform untaint` (o recurso em si tinha sido criado normalmente, só a checagem pós-criação falhou) em vez de destruir e recriar à toa.
2. **Quem roda o Terraform localmente também precisa de `Storage Blob Data Contributor`** no Storage Account do state — "Owner"/"Contributor" da assinatura **não bastam**: são papéis só de controle (`dataActions` vazio no Azure RBAC), sem acesso de dado ao blob. Só tinha dado esse papel pro Service Principal do GitHub Actions; adicionei `azurerm_role_assignment.operador_state_storage` no bootstrap pra quem aplica localmente também.
3. **`azurerm_storage_table` é incompatível com `shared_access_key_enabled = false`**: o recurso sempre tenta ler/gravar a ACL (stored access policy) da tabela, e essa API específica do Table Storage **nunca suportou Azure AD** — só chave (confirmado: nem `az storage table policy` aceita `--auth-mode login`). Sem contorno no lado do Terraform. Removidas as 4 tabelas do `infra/storage.tf` — quem cria as tabelas agora é o próprio `New-TabelaSeNaoExistir` (módulo Storage, T05), que já roda via REST puro com Managed Identity sem essa limitação (criar tabela é uma operação diferente de gerenciar ACL), chamado no início de toda `Invoke-VerificacaoDiaria` (T07) e por `tools/Import-Itens.ps1`.
4. **`Microsoft.Communication` não estava registrado na assinatura** — comum em assinaturas novas/pessoais. Resolvido com `az provider register --namespace Microsoft.Communication` (ação de assinatura, não parte do Terraform — documentado no `infra/README.md` como pré-requisito do primeiro apply).
5. **`FunctionExecutionCount` não existe no Flex Consumption** (confirmado com `az monitor metrics list-definitions` contra a Function real já implantada — o Flex expõe `OnDemandFunctionExecutionCount`/`AlwaysReadyFunctionExecutionCount`, sem dimensão de falha). O alerta de falha (`budget-alertas.tf`) virou baseado em **log** (`azurerm_monitor_scheduled_query_rules_alert_v2`, KQL contra o Log Analytics) em vez de métrica de plataforma — usa o mesmo texto (`"Falha ["`) que `run.ps1` já grava via `Write-Warning` (T08). Precisou de `skip_query_validation = true` porque a Workspace nasce vazia (a tabela `traces` só existe depois da primeira telemetria ingerida).
6. **O sender username `"DoNotReply"` já existe por padrão** assim que o domínio gerenciado é criado — o Azure provisiona automaticamente. Removido o `azurerm_email_communication_service_domain_sender_username` explícito (dava "already exists").
7. **O mais grave: `AzureWebJobsStorage` e `DEPLOYMENT_STORAGE_CONNECTION_STRING` são injetados automaticamente pela plataforma como connection string de CHAVE** — vêm com a chave vazia (`AccountKey=;...`) porque `shared_access_key_enabled = false` (D3), e isso **derruba o host inteiro** (`func-mvenc-dev` ficava em loop de crash: "There was an error performing a read operation on the Blob Storage Secret Repository" / "An unhandled host error has occurred", visível no Application Insights). Não é algo que o Terraform rastreia (não aparece no `app_settings` do state — `terraform plan` não via diferença nenhuma mesmo removendo os dois manualmente). Corrigido com `AzureWebJobsStorage__accountName` (conexão baseada em identidade, precisa também de `Storage Queue Data Contributor` além dos papéis já existentes) **e** um `null_resource` com `local-exec` (`az webapp config appsettings delete`) que roda depois da Function App e dos papéis, pra remover as duas entradas quebradas em todo `apply` — sem isso, um `destroy`+`apply` do zero reproduziria o mesmo travamento.

**Confirmado nesse apply real** (as pendências que tinham ficado em aberto): `"AzureManagedDomain"` É o nome aceito pelo `domain_management = "AzureManaged"`; `from_sender_domain` É o atributo certo pro `ACS_REMETENTE` (saiu `DoNotReply@<guid>.azurecomm.net`, formato esperado). **O papel `"Communication and Email Service Owner"` (único disponível, `dataActions` vazio) funciona** — disparei `VerificacaoDiaria` de verdade contra o ambiente implantado (`POST /admin/functions/VerificacaoDiaria` com a function key) e ela rodou com sucesso ("Executed... Succeeded", ~20s de duração — compatível com o polling real do `Send-EmailAcs` até o ACS confirmar o envio — sem nenhuma exceção nos logs), disparando o e-mail de resumo pro `ADMIN_EMAIL`. **Confirmado pelo usuário em 2026-09-25**: e-mail recebido de verdade ("Monitor de Vencimentos: resumo diário", 0 itens verificados — ambiente sem itens cadastrados ainda). Pipeline completo (Function → Storage via Managed Identity → ACS Email via Managed Identity → caixa de entrada) validado de ponta a ponta na Azure real.

Infra final em `rg-mvenc-dev`: Storage Account (`stmvencdev<sufixo>`), Function App (`func-mvenc-dev`, testada e funcionando de ponta a ponta), ACS/Email, Log Analytics + App Insights, Key Vault, budget e alerta — tudo aplicado, `terraform plan` final sem diferenças (drift zero).

### T10 — CI/CD (GitHub Actions) ✅ Concluída (2026-09-25)
**Entrega:** `.github/workflows/ci.yml` (PR e push: PSScriptAnalyzer, Pester sem tag `Integration`, `terraform fmt/validate`) e `deploy.yml` (push na `main` ou manual: `azure/login` via OIDC → `terraform apply` → zip de `src/functions` + módulos → `Azure/functions-action`).
**Aceite:** CI verde em um PR de teste. **[HUMANO]** configurar variáveis do repositório (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`) e o environment `dev` com aprovação manual.
**Pendências:**
- **Branch é `master`, não `main`** — o repositório real usa `master` (confirmado com `gh repo view`); os dois workflows disparam em `push: branches: [master]`, não `main` como o texto da tarefa sugeria.
- **Achei e corrigi um problema real de empacotamento** enquanto montava o `deploy.yml`: `src/functions/` e `src/modules/` são pastas *irmãs* no repositório (`profile.ps1` importa via `../modules/...`), mas um zip deploy do Azure Functions vira a raiz do site (`wwwroot`) — não existe "um nível acima" depois de implantado. Sem ajuste, `profile.ps1` quebraria em produção mesmo funcionando perfeitamente local. Resolvido de dois jeitos, juntos: (1) `profile.ps1` agora procura o módulo em `./modules/...` (layout implantado) **e** `../modules/...` (layout local do repo), usando o que existir; (2) o passo de empacotamento do `deploy.yml` monta um diretório `staging/` com `modules/` copiado pra dentro, ao lado de `profile.ps1`, antes de zipar. Testado manualmente simulando os dois layouts — os dois funcionam.
- **CI roda Pester nas duas versões de PowerShell** (`shell: pwsh` e `shell: powershell`, ambas disponíveis no runner `windows-latest`) — mesmo rigor que foi mantido manualmente em T02–T09. Precisa de `Import-Module Pester -MinimumVersion 5.0.0 -Force` explícito antes de rodar, porque o Windows já vem com um Pester 3.4.0 embutido em `System32\WindowsPowerShell` que senão teria precedência.
- **`terraform validate` do `ci.yml` não loga na Azure** (nem precisa — `-backend=false` no `infra/` e state local no `bootstrap/`); só o `deploy.yml` usa a identidade OIDC (`azure/login` + variáveis `ARM_*` pro provider/backend do Terraform).
- **Job de `deploy.yml` é único** (apply direto, sem um job de `plan` separado pra revisar antes do apply) — o gate de aprovação do GitHub Environment `dev` já para o job inteiro antes de qualquer passo rodar, mas não mostra o plano pra revisão nesse ponto. Um plan/apply em dois jobs seria mais seguro (comum em produção), mas ficou fora de escopo por ora — projeto pessoal, quem aprova é quem também revisou o `terraform plan` local antes de commitar.
- **Não testável de verdade sem um PR real no GitHub** (o aceite pede "CI verde em um PR de teste") — validei localmente tudo que dava pra validar sem isso: YAML bem formado (`npx js-yaml`), a lógica do `Invoke-Pester -CI` falha o processo corretamente em teste quebrado (testado com um teste-cobaia), e o empacotamento simulado dos dois layouts do `profile.ps1`. O primeiro PR real de teste é o próximo passo natural (pode ser este commit virando PR, se quiser).
- **Correção posterior (2026-09-25, antes do primeiro push público):** o passo de lint do `ci.yml` estava quebrado — `Invoke-ScriptAnalyzer -Path` aceita **um** caminho só; `-Path ./src, ./agent, ./tools` falha com "Cannot convert System.Object[] to System.String" (não era problema de aspas do bash, como eu tinha suposto na T08). Agora itera um caminho por vez e filtra o falso positivo conhecido do `requirements.psd1`. `deploy.yml` virou só `workflow_dispatch` (sem push automático) e lê `ADMIN_EMAIL` de variável do repositório (`TF_VAR_*`), já que o e-mail saiu do `dev.tfvars` versionado (agora em `infra/pessoal.auto.tfvars`, fora do Git).
- **`Azure/functions-action@v1`** — não consegui confirmar contra a documentação atual (sem acesso à internet além do registry do Terraform/npm) se essa action lida com Flex Consumption sem parâmetro extra; se o deploy falhar especificamente nesse passo, é o primeiro lugar a checar na T12.

### T11 — Documentação e LGPD ✅ Concluída (2026-09-25)
**Entrega:** `README.md` completo (o que faz / o que **não** faz — nunca chave privada, `.pfx` ou senha), `docs/privacidade.md` (dados coletados, finalidade, retenção de 12 meses, local de armazenamento), `docs/runbook.md` (como cadastrar itens, reprocessar um dia, trocar contato, investigar falha no App Insights, rotacionar configurações).
**Aceite:** alguém que não conhece o projeto consegue subir localmente e cadastrar um item só lendo o README.
**Pendências:**
- **Aceite testado de verdade, não só escrito**: segui o `README.md` do zero como alguém que nunca viu o projeto — `Start-Local.ps1` → cadastrar um item novo seguindo só a tabela de colunas do README → `func start` → disparar via API admin → o item apareceu no e-mail gerado, junto com os 4 de exemplo. Fluxo completo, sem precisar olhar código.
- **`docs/runbook.md` é honesto sobre uma lacuna real**: "reprocessar o dia de hoje" funciona (idempotente, já suportado desde a T07); "reprocessar um dia *passado*" **não tem suporte direto hoje** — `run.ps1` nunca passa `-Hoje` pra `Invoke-VerificacaoDiaria`, então não dá pra mandar uma data diferente pela API HTTP. Documentei isso como limitação conhecida em vez de inventar uma solução, com a melhoria futura óbvia anotada (expor `-Hoje` por um parâmetro HTTP admin).
- **`docs/runbook.md` também documenta uma limitação de acesso**: como o Storage não aceita chave (`shared_access_key_enabled = false`, D3), não tem hoje um jeito direto de rodar `tools/Import-Itens.ps1` da máquina local contra o Storage de `dev` implantado — só a própria Function (via Managed Identity) escreve lá. Anotado com as alternativas (Storage Explorer com papel próprio, ou melhoria futura).
- **`docs/privacidade.md`** cobre LGPD de forma concreta (o que cada tabela guarda, o que nunca é coletado, retenção de 12 meses em `Verificacoes` já automática desde a T07, com quem os dados são compartilhados — ACS pro envio, RDAP só recebe o nome do domínio) — deixando claro que hoje é projeto pessoal/portfólio (D13), não uma operação comercial com base legal de cliente pagante.
- `docs/arquitetura.md` estava desatualizado desde a T05/T09 (mencionava Key Vault guardando credenciais de e-mail, que nunca existiu — tudo é Managed Identity; PowerShell 7.4; RG "um por ambiente dev/prod") — corrigido para bater com o que foi implementado e com D13/D14.

### T12 — Deploy em dev e teste real [HUMANO + Sonnet]
- [x] Deploy manual (via `func azure functionapp publish`, não pela pipeline do GitHub Actions ainda — T10 só ficou com o `.yml` escrito, faltam as variáveis do repositório) — 2026-09-25.
- [x] Testado de ponta a ponta contra a Azure real: `VerificacaoDiaria` disparada manualmente, rodou sem erro, e-mail de resumo diário **recebido de verdade** pelo usuário (0 itens — sem cadastro ainda). Achados e correções documentados na T09/pendências acima.
- [ ] Deploy via pipeline do GitHub Actions (falta configurar `AZURE_CLIENT_ID`/`AZURE_TENANT_ID`/`AZURE_SUBSCRIPTION_ID` como variáveis do repositório e o Environment `dev` com aprovação manual — T10).
- [ ] Cadastrar alguns itens de teste (domínios/sites públicos ou seus, um `Manual`/`CertA3` com data fictícia próxima — nada disso exige comprar nada) e ajustar datas para disparar cada marco; conferir recebimento, entrega fora do spam e deduplicação.
- [ ] Deixar rodando alguns dias (o timer real, não só disparo manual) e conferir o resumo diário do admin nesse regime.

### Piloto (30 dias) — fora de escopo por ora (ver ADR 0013)
> Decisão de 2026-09-25: o projeto fica de uso pessoal/portfólio, sem meta de clientes pagantes nem domínio próprio. A infra (`dev`) fica de pé sob demanda, sem custo relevante quando parada. Esta seção fica registrada como possibilidade futura, não como próximo passo.
- [ ] 2–3 clientes com permissão por escrito; montar o CSV de cada um; definir destinatários.
- [ ] Ambiente `prod` + domínio próprio no ACS com SPF, DKIM e DMARC.
- [ ] Coletar feedback: utilidade dos marcos, clareza do e-mail, itens que faltaram.

---

## Fase 2 — Agente A1 (opcional, sem dependência do Piloto)

> **Premissa (confirmada em 2026-09-22):** não teremos acesso remoto às máquinas dos clientes onde o certificado A1 está instalado. Por isso o agente precisa ser autoinstalável — o cliente (ou o TI dele) executa o instalador (T23) uma vez, e daí em diante só há tráfego de saída da máquina dele para a API (T21). Nenhuma tarefa desta fase pode assumir acesso direto/remoto a essas máquinas.

- **T20** Especificação da API `ReceberAgente` (contrato JSON, versionamento, limites de tamanho) + ADR.
- **T21** Function HTTP `ReceberAgente`: valida chave de API (hash na tabela `Clientes`, comparação em tempo constante), valida payload, upsert em `Itens` com `Tipo=CertA1`, RK = thumbprint.
- **T22** Agente `agent/Coletar-CertificadosA1.ps1` compatível com **PowerShell 5.1**: lê `Cert:\CurrentUser\My` e `Cert:\LocalMachine\My`, filtra emissores ICP-Brasil (lista configurável), envia só metadados; log local; nunca exporta chave privada.
- **T23** Instalador `agent/Instalar-Agente.ps1` (tarefa agendada diária + no logon, para pegar o repositório do usuário) e desinstalador.
- **T24** Tratamento de A1 que sumiu da máquina (renovado ou removido) e testes.
- **[HUMANO]** Se for testar de verdade: levantar a lista de ACs ICP-Brasil dos próprios certificados (mesmo sem piloto, dá pra testar com certificados do próprio usuário) e as versões de Windows-alvo.

## Fase 3 — Produto — fora de escopo (ver ADR 0013)

Multi-tenant por `ClienteId` com validação em toda a API → portal em Static Web Apps (auth Entra External ID) → canais Teams/WhatsApp → relatório mensal → cobrança e planos. Pré-requisitos **[HUMANO]**: forma jurídica (contador), termos de uso e política de privacidade, nome (INPI + domínio), meio de cobrança, pesquisa de preço com 3–5 clientes. Dependia do Piloto (agora fora de escopo) — fica registrada só como referência de até onde o desenho original ia.

---

## Ordem e dependências

```
M0 → T01 → T02 → T03 ┐
                T04 ┘→ T05 → T06 → T07 → T08 → T09 → T10 → T11 → T12 → (fim do escopo ativo)
```

Piloto e Fase 3 ficam fora do escopo ativo (ver ADR 0013). Fase 2 (agente A1) é opcional/futura, sem depender do Piloto.

T11 pode ser escrito aos poucos a partir da T08.
