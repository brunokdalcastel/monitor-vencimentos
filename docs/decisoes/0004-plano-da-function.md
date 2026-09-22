# ADR 0004 — Plano da Function App

## Contexto

É preciso escolher um plano de hospedagem para a Function App que minimize custo (volume baixo de execuções: uma vez ao dia) e suporte PowerShell 7.x com identidade gerenciada.

## Decisão

Usar **Flex Consumption**, com **PowerShell 7.4** em **Linux**.

## Consequências

- Cota gratuita cobre confortavelmente o volume esperado (uma execução diária).
- Managed Identity disponível nativamente.
- Flex Consumption não suporta managed dependencies (ver [ADR 0002](0002-acesso-ao-table-storage.md)) nem `WEBSITE_TIME_ZONE` (ver [ADR 0006](0006-horario.md)).
- **Fallback:** caso a combinação Flex Consumption + PowerShell 7.4 não esteja disponível na região escolhida (validar na T09), usar o plano **Consumption** (Windows) como alternativa.
