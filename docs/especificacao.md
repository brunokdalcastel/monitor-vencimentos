# Monitor de Vencimentos — Especificação do Projeto

> Nome provisório. Repositório privado no GitHub → MVP em Azure → produto.
> Objetivo: nunca mais um cliente parado por certificado, SSL ou domínio vencido.

---

## 1. Problema e proposta de valor

**Problema:** certificados digitais ICP-Brasil (A1/A3), certificados SSL e domínios vencem sem aviso. Para cartórios, prefeituras e pequenas empresas, isso significa operação parada, atendimento emergencial e desgaste com o cliente.

**Solução:** monitoramento automático e centralizado de todos os vencimentos, com alertas escalonados (30, 15 e 7 dias, e no dia do vencimento) para o responsável técnico e para o cliente.

**Público-alvo:**
- MSPs e técnicos de TI que atendem vários clientes (modelo revenda)
- Cartórios, escritórios de contabilidade e advocacia (uso intenso de certificado digital)
- Pequenas empresas com site e domínio próprios

---

## 2. Escopo por fase

### Fase 1 — MVP (uso próprio / piloto)
- [ ] Inventário de itens monitorados (Table Storage)
- [ ] Verificação de **SSL** (conexão na porta 443, leitura do `NotAfter`)
- [ ] Verificação de **domínio .br** via RDAP do Registro.br (`https://rdap.registro.br/domain/<dominio>`, evento `expiration`)
- [ ] **Certificados A3** e itens manuais: cadastro da data de validade
- [ ] Execução diária (Function com timer trigger)
- [ ] Alerta por e-mail aos 30, 15, 7 e 0 dias
- [ ] Log de execução e de alertas enviados (não repetir alerta do mesmo marco)

### Fase 2 — Coleta automática de A1
- [ ] Script agente em PowerShell executado via **Agendador de Tarefas do Windows** (ou GPO) nas máquinas do cliente
- [ ] Leitura de `Cert:\CurrentUser\My` e `Cert:\LocalMachine\My`, filtrando emissores ICP-Brasil
- [ ] Envio **somente de metadados** (titular, CN, emissor, thumbprint, validade, hostname) para uma Function HTTP
- [ ] Autenticação do agente por chave de API por cliente
- [ ] Instalador simples (script de implantação do agente)

### Fase 3 — Produto
- [ ] Multi-cliente (multi-tenant): isolamento dos dados por `ClienteId`
- [ ] Portal web (Static Web Apps) para o cliente cadastrar itens e ver o painel
- [ ] Alertas por outros canais (Teams, WhatsApp)
- [ ] Relatório mensal em PDF/e-mail por cliente
- [ ] Cobrança e gestão de planos

---

## 3. Arquitetura (Azure)

```
[Timer diário] → Azure Function (PowerShell)
                    ├─ lê inventário ........ Table Storage
                    ├─ checa SSL ............ conexão TLS 443
                    ├─ checa domínio ........ RDAP Registro.br
                    ├─ grava resultado ...... Table Storage
                    └─ envia alertas ........ E-mail (ACS Email ou Graph API)

[Agente A1 no cliente] → Function HTTP (chave de API) → Table Storage   (fase 2)
[Portal do cliente]    → Static Web Apps → API → Table Storage          (fase 3)
```

| Recurso | Uso | Observação |
|---|---|---|
| Resource Group | Agrupar tudo | Um por ambiente (dev/prod) |
| Storage Account | Table Storage (inventário, resultados, log) + armazenamento da Function | Custo de centavos |
| Function App (plano de consumo / Flex Consumption) | Verificações e API | Confirmar suporte a PowerShell 7.x no plano escolhido |
| Key Vault | Segredos (chaves de API, credenciais de envio de e-mail) | Function acessa via Managed Identity |
| Azure Communication Services — Email | Envio de alertas com domínio próprio | Alternativa: Graph API com caixa M365 |
| Application Insights | Logs e falhas | Definir limite diário de ingestão para não gerar custo |
| Static Web Apps (fase 3) | Portal do cliente | Plano gratuito para começar |

**Infraestrutura como código:** Terraform (entra no portfólio).
**CI/CD:** GitHub Actions com autenticação OIDC (federated credential, sem segredo armazenado).

---

## 4. Modelo de dados (Table Storage)

**Tabela `Itens`** — PartitionKey = `ClienteId`, RowKey = `ItemId`

| Campo | Exemplo |
|---|---|
| Tipo | `SSL` / `Dominio` / `CertA1` / `CertA3` / `Manual` |
| Alvo | `portal.cliente.com.br:443`, `cliente.com.br`, thumbprint |
| Descricao | "e-CNPJ A3 do tabelião" |
| Titular | Nome/CNPJ do titular (só se necessário) |
| DataVencimento | `2027-03-15` (automático ou cadastrado) |
| ContatosAlerta | e-mails separados por `;` |
| Ativo | `true` |

**Tabela `Verificacoes`** — resultado de cada checagem (data, status, dias restantes, erro).
**Tabela `AlertasEnviados`** — ItemId + marco (30/15/7/0) para não duplicar envio.
**Tabela `Clientes`** — nome, plano, contato principal, chave de API (hash).

---

## 5. Informações que preciso levantar

### Técnicas
- [ ] Assinatura Azure para o projeto (pessoal, separada de qualquer empregador)
- [ ] Região: **Brazil South** (latência e argumento de dados no Brasil) × **East US** (mais barata) — comparar na calculadora
- [ ] Domínio próprio para o produto e para envio de e-mail (SPF, DKIM e DMARC configurados)
- [ ] Método de envio de e-mail: ACS Email × Graph API
- [ ] Lista de emissores ICP-Brasil a filtrar no agente A1 (ACs mais usadas pelos clientes-alvo)
- [ ] Versões de Windows das máquinas onde o agente vai rodar (PowerShell 5.1 × 7)
- [ ] Como as datas dos certificados **A3** serão cadastradas (na emissão, por planilha, pelo portal)
- [ ] Canais de alerta desejados além do e-mail (Teams? WhatsApp?)
- [ ] Custo da API oficial do WhatsApp (Meta Business, cobrança por conversa) se for oferecer esse canal

### Piloto
- [ ] 2 ou 3 clientes/conhecidos para testar (idealmente um escritório contábil ou um cartório, com permissão por escrito)
- [ ] Lista de itens de cada um: domínios, sites, certificados A1/A3 e datas
- [ ] Quem recebe cada alerta

### Negócio e jurídico
- [ ] **Separação do empregador:** conferir contrato de trabalho (cláusulas de exclusividade, não concorrência e propriedade intelectual). Desenvolver fora do horário, em equipamento e conta próprios, sem usar dados ou clientes da empresa sem acordo formal. Alternativa: oferecer o produto à própria empresa como parceria ou revenda.
- [ ] Forma jurídica para faturar (MEI permite essa atividade? ou ME no Simples) — consultar contador
- [ ] Termos de uso e política de privacidade (LGPD): quais dados são coletados, por quanto tempo, onde ficam
- [ ] Nome do produto e verificação de disponibilidade (INPI e domínio)
- [ ] Meio de cobrança recorrente (boleto/PIX recorrente/cartão)

---

## 6. Segurança e LGPD

- **Nunca** coletar chave privada, arquivo `.pfx` ou senha de certificado — somente metadados.
- Chaves de API por cliente, armazenadas como hash; segredos no Key Vault.
- Managed Identity para a Function acessar Storage e Key Vault (sem connection string em código).
- Dados isolados por cliente (PartitionKey + validação na API).
- Retenção definida (ex.: histórico de verificações por 12 meses).
- Documentar no README o que o agente faz e o que ele **não** faz — isso é argumento de venda.

---

## 7. Custos de nuvem (estimativa — validar na Azure Pricing Calculator)

| Item | Estimativa mensal |
|---|---|
| Function (consumo) | Dentro ou perto da cota gratuita para esse volume |
| Storage Account (tabelas) | Centavos |
| Key Vault | Centavos (cobrança por operação) |
| E-mail (ACS) | Centavos por milhares de e-mails — confirmar tabela atual |
| Application Insights | Zero a poucos dólares com limite de ingestão configurado |
| **Total esperado (até ~50 clientes)** | **Poucos dólares por mês** |

Configurar **orçamento com alerta** (Cost Management → Budgets) desde o primeiro dia.

---

## 8. Precificação do produto (hipóteses para validar)

O custo de nuvem por cliente é praticamente zero; o preço reflete o **risco evitado** (cliente parado) e o tempo de suporte.

| Plano | Para quem | Inclui | Preço sugerido |
|---|---|---|---|
| **Essencial** | Pequena empresa | Até 10 itens (SSL, domínio, A3 cadastrado), alertas por e-mail | R$ 39–59/mês |
| **Profissional** | Cartório, contabilidade | Até 40 itens, agente de coleta A1, alertas para vários contatos, relatório mensal | R$ 99–149/mês |
| **Revenda MSP** | MSPs e técnicos | Painel multi-cliente, marca própria nos alertas | R$ 15–25 por cliente final/mês (mínimo de 10) |

**Opcionais:**
- Implantação do agente A1: taxa única (ex.: R$ 150–300 por cliente)
- Alertas por WhatsApp: adicional mensal que cubra o custo da API

**Exemplo de conta:** 15 clientes no Profissional a R$ 119 = **R$ 1.785/mês**, com custo de nuvem de poucos dólares.

**Validação de preço antes de fixar:**
- [ ] Pesquisar concorrentes (ferramentas de monitoramento de SSL/domínio e gestão de certificados digitais oferecidas por ACs e contadores)
- [ ] Perguntar a 3–5 potenciais clientes quanto custa hoje um dia parado por certificado vencido
- [ ] Oferecer o piloto gratuito por 60 dias em troca de feedback e depoimento

---

## 9. Estrutura do repositório

```
monitor-vencimentos/
├── README.md
├── docs/
│   ├── arquitetura.md
│   ├── decisoes/            # ADRs (registro de decisões)
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
├── agent/                   # script do agente A1 + instalador
├── tests/                   # Pester
└── .github/workflows/       # lint (PSScriptAnalyzer), testes, deploy
```

---

## 10. Próximos passos

1. [ ] Criar o repositório privado e a estrutura acima
2. [ ] Terraform do ambiente `dev` (RG, Storage, Function, Key Vault, orçamento)
3. [ ] Função de verificação de SSL + testes Pester
4. [ ] Função de verificação de domínio (RDAP) + testes
5. [ ] Leitura do inventário e envio de alerta por e-mail
6. [ ] Piloto com 2–3 clientes por 30 dias
7. [ ] Fase 2 (agente A1) conforme o feedback do piloto
