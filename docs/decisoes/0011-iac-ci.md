# ADR 0011 — Infraestrutura como código e CI/CD

## Contexto

Toda a infraestrutura precisa ser reprodutível entre `dev` e `prod`, versionada, e o deploy não deve depender de segredos de longa duração armazenados no GitHub.

## Decisão

- **IaC:** Terraform (`azurerm` 4.x), com o `state` guardado em uma Storage Account separada (`infra/bootstrap/`, provisionada uma única vez manualmente).
- **CI/CD:** GitHub Actions, autenticando no Azure via **OIDC** (federated credential), sem client secret armazenado.

## Consequências

- Todo recurso Azure do projeto (exceto o bootstrap do state) é criado e alterado via Terraform — nada manual no portal (ver regra em `CLAUDE.md`).
- O pipeline de deploy não guarda segredo de longa duração; a federated credential é escopada ao repositório/branch.
- Exige configurar variáveis do repositório (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`) e um environment `dev` com aprovação manual (T10, [HUMANO]).
