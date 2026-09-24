# Privacidade e LGPD

> Este documento descreve, de forma concreta (não genérica), quais dados o Monitor de
> Vencimentos coleta, para quê, onde ficam armazenados e por quanto tempo — pensado pra
> LGPD (Lei 13.709/2018), mas escrito para ser lido e entendido sem ser advogado.

## Contexto: projeto pessoal, não um produto comercial

Este é um projeto de uso pessoal/portfólio (ver [ADR 0013](decisoes/0013-escopo-pessoal-sem-piloto.md)):
não há clientes pagantes, não há termos de uso publicados, não há uma empresa por trás.
Quem opera o sistema (cadastra itens, define contatos) é o próprio autor do projeto, para
os próprios itens (ou itens de teste). Este documento existe mesmo assim porque:

1. É uma boa prática documentar isso desde já, antes de qualquer uso com dados de terceiros.
2. Fica pronto caso o projeto um dia evolua para um piloto real (ver "Fora de escopo" no `PLANO.md`).
3. Contatos de alerta (e-mails de terceiros, se você cadastrar itens de outra pessoa) já
   são dado pessoal, mesmo em uso pessoal — vale documentar como são tratados.

## Dados coletados

Tudo fica em quatro tabelas do Azure Table Storage (`infra/`), na região Brazil South
(D5), sem replicação geográfica fora do Brasil (`LRS`).

### Tabela `Itens` (inventário cadastrado)

| Campo | O que é | Dado pessoal? |
|---|---|---|
| `ClienteId` / `ItemId` | Identificadores internos | Não |
| `Tipo` | `SSL`, `Dominio`, `CertA1`, `CertA3`, `Manual` | Não |
| `Alvo` | Host/domínio verificado, ou descrição do item manual/A3 | Não (em geral) |
| `Descricao`, `Titular` | Texto livre — ex.: "e-CNPJ da Diretoria", "Empresa X LTDA" | Pode conter nome/CNPJ de uma pessoa/empresa |
| `DataVencimento` | Data de validade (automática ou cadastrada) | Não |
| `ContatosAlerta` | E-mails que recebem o alerta | **Sim** — dado pessoal (e-mail) |
| `Ativo` | Se o item está sendo monitorado | Não |

### Tabela `Verificacoes` (histórico de checagens)

Resultado de cada verificação diária: `Tipo`, `Alvo`, `DataVencimento` apurada,
`Sucesso`/`Erro`. Nenhum dado pessoal além do que já está em `Itens` (via `Alvo`).

### Tabela `AlertasEnviados` (deduplicação)

`ItemId`, `DataVencimento`, `Marco`, `DataEnvio` — só o suficiente para não duplicar
alertas (ver [ADR 0008](decisoes/0008-deduplicacao-de-alertas.md)). Nenhum e-mail é
gravado aqui (o e-mail já está em `Itens.ContatosAlerta`).

### Tabela `Clientes` (ainda não usada)

Prevista para a Fase 2/3 (agente A1, multi-tenant) — hoje vazia, sem uso no MVP.

## O que **nunca** é coletado

- Chave privada, arquivo `.pfx` ou senha de certificado — em nenhuma hipótese, em
  nenhuma tabela, em nenhum log. Só metadados públicos do certificado (emissor,
  validade, thumbprint, cadeia) — o mesmo que qualquer navegador vê ao acessar o site.
- Conteúdo de e-mails de terceiros, dados de navegação, geolocalização, ou qualquer
  dado que não esteja listado acima.

## Finalidade

Exclusivamente: verificar o vencimento dos itens cadastrados e notificar os contatos
configurados. Não há perfilamento, não há venda/compartilhamento de dados para
publicidade, não há analytics de terceiros rastreando quem abre os e-mails.

## Base legal (LGPD)

Os e-mails de contato são fornecidos por quem cadastra o item (execução de um serviço
solicitado pelo próprio titular dos dados, ou por quem tem relação direta com ele —
ex.: cadastrar o contato de TI de uma empresa da qual você já é responsável). Não há
coleta de terceiros sem relação direta com quem opera o sistema.

## Retenção

| Tabela | Retenção |
|---|---|
| `Verificacoes` | **12 meses** — limpeza automática todo dia, feita pelo próprio orquestrador (`Remove-VerificacaoAntiga`, ver T07) |
| `Itens` | Enquanto existir/estiver `Ativo=true`. Sem expiração automática — remover ou desativar (`Ativo=false`) é manual (ver `docs/runbook.md`) |
| `AlertasEnviados` | Enquanto o item existir (usado para deduplicação — apagar antes da hora reabre alertas já enviados) |

## Onde os dados ficam / com quem são compartilhados

- **Armazenamento**: Azure Table Storage, Brazil South, acesso só via Managed Identity
  (sem chave — `shared_access_key_enabled = false`, ver [ADR 0003](decisoes/0003-autenticacao.md)).
- **Envio de e-mail**: Azure Communication Services (subprocessador Microsoft/Azure)
  recebe o endereço de contato e o conteúdo do alerta para entregar a mensagem — é o
  único terceiro que recebe dado pessoal (o e-mail de contato) neste sistema.
- **Verificação de domínio (RDAP)**: consulta `rdap.registro.br` ou `rdap.org` enviando
  só o **nome do domínio verificado** — nenhum dado pessoal do titular do item viaja
  nessa consulta.
- **Verificação de SSL**: conexão TLS direta com o host verificado (porta 443) — não
  envia nem recebe dado pessoal, só lê o certificado público apresentado pelo servidor.

## Direitos do titular (acesso, correção, exclusão)

Como quem opera o sistema hoje é o próprio autor (D13), pedidos de acesso/correção/
exclusão de um contato cadastrado são resolvidos diretamente: editar ou remover a
linha correspondente na tabela `Itens` (ver "Trocar contato" e "Remover um item" em
[`runbook.md`](runbook.md)). Se este projeto vier a ter usuários reais no futuro, este
documento será revisado para incluir um canal de contato formal.

## Segurança

Ver a seção "Segurança (inegociável)" em [`CLAUDE.md`](../CLAUDE.md): Managed Identity
em tudo, nenhum segredo versionado, HTTPS/TLS em todas as chamadas externas, escape de
HTML/OData em todo campo vindo de cadastro.
