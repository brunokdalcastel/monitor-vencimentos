# ADR 0003 — Autenticação no Table Storage

## Contexto

O código de acesso ao Table Storage (ver [ADR 0002](0002-acesso-ao-table-storage.md)) precisa funcionar tanto em produção (Azure real) quanto em desenvolvimento local (Azurite), sem exigir segredos em produção.

## Decisão

- **Produção:** token da **Managed Identity**, obtido via `IDENTITY_ENDPOINT`/`IDENTITY_HEADER`.
- **Local:** **SharedKey** contra o Azurite, configurado por `TABELAS_MODO_AUTH`.

## Consequências

- O mesmo código (`New-CabecalhoTabela`) atende os dois ambientes, alternando apenas pela variável de ambiente `TABELAS_MODO_AUTH`.
- Nenhum segredo de produção é necessário; a chave do Azurite é pública e conhecida (uso exclusivamente local).
- Testes de integração (tag `Integration`) rodam contra Azurite sem depender de uma assinatura Azure real.
