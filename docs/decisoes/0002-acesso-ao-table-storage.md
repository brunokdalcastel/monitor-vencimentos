# ADR 0002 — Acesso ao Table Storage

## Contexto

A Function App roda em **Flex Consumption**, plano que **não suporta managed dependencies** (módulos PowerShell pré-instalados como `Az` ou `AzTable`), o que inviabiliza depender deles no código da Function.

## Decisão

Implementar um **wrapper REST próprio** (`Invoke-RestMethod`) para todas as operações no Table Storage (CRUD, paginação, autenticação), em vez de usar módulos `Az`/`AzTable`.

## Consequências

- Zero dependências externas no pacote de deploy da Function — pacote simples e previsível.
- Mais código próprio para manter (cabeçalhos de autenticação, paginação via `x-ms-continuation-*`, escape de filtros OData), coberto por testes unitários (T05).
- Facilita suportar os dois modos de autenticação (Managed Identity em prod, SharedKey local) com o mesmo wrapper.
