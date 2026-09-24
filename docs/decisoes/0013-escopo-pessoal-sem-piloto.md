# ADR 0013 — Escopo pessoal/portfólio, sem piloto pago nem domínio próprio

## Contexto

O plano original (Piloto, Fase 3) previa evoluir o projeto para um produto com clientes
pagantes, exigindo domínio próprio (SPF/DKIM/DMARC para o ACS), forma jurídica, termos de
uso e política de privacidade. O usuário decidiu, em 2026-09-25, que não vai comprar
domínio nem buscar clientes reais — o projeto fica de uso pessoal e como peça de
portfólio, com a infraestrutura em pé sob demanda (subir quando quiser testar/demonstrar,
sem custo relevante enquanto parada).

## Decisão

- Piloto (30 dias) e Fase 3 (produto multi-tenant) saem do escopo ativo do `PLANO.md`,
  mantidas só como registro do desenho original.
- Só existe o ambiente `dev` — não há `environments/prod.tfvars` nem meta de domínio
  próprio no ACS. `dev` continua usando o domínio gerenciado pelo Azure (D1), sem custo.
- T09/T10 (Terraform + CI/CD via GitHub Actions) continuam de pé como planejado —
  decisão explícita do usuário, já que a IaC e o pipeline são também parte do valor de
  portfólio do projeto, independente de haver clientes reais.
- Fase 2 (agente A1) deixa de depender do Piloto: pode ser feita (ou não) como
  demonstração técnica, testando com os próprios certificados do usuário.

## Consequências

- Nenhum recurso de domínio (registro, DNS, SPF/DKIM/DMARC) entra no escopo ativo.
- Custo esperado da infra `dev` parada: próximo de zero (Function App Flex Consumption
  só cobra por execução; Table Storage e Application Insights ficam dentro dos tiers
  baratos/sempre-gratuitos nesse volume; ACS Email cobra centavos por e-mail enviado,
  irrelevante em uso esporádico de teste) — coberto pelo budget de R$50/mês já
  configurado (M0.2).
- Se o usuário decidir no futuro perseguir um piloto real, esta decisão pode ser revista
  com um novo ADR; o desenho original (Piloto/Fase 3) continua documentado no `PLANO.md`
  como referência.
