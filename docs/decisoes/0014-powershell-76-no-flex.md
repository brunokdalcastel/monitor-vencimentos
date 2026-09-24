# ADR 0014 — PowerShell 7.6 no Flex Consumption (revisão da D4)

## Contexto

A D4 original fixava PowerShell 7.4 na Function App. Checando a disponibilidade antes de
codar a T09 (`az functionapp list-flexconsumption-runtimes --location brazilsouth --runtime
powershell`), o suporte a 7.4 no Flex Consumption termina em 10/nov/2026 — poucas semanas
a partir de quando esta decisão foi tomada (2026-09-25). A versão padrão atual do runtime é
a 7.6 (fim de vida em 2028).

## Decisão

A Function App (`infra/`) usa PowerShell **7.6**, não 7.4.

## Consequências

- O código (`src/modules/`, `src/functions/`) foi escrito e testado contra PowerShell
  7.4.20 e Windows PowerShell 5.1, sem usar nada exclusivo do 7.4 — a expectativa é que
  funcione sem alterações no 7.6, mas isso só é confirmado de fato no primeiro deploy real
  (T12), já que não havia 7.6 disponível para testar localmente nesta máquina no momento
  desta decisão.
- `PSScriptAnalyzerSettings.psd1` continua mirando `7.4` e `5.1` em `PSUseCompatibleSyntax`
  — não precisa mudar, já que é compatibilidade *retroativa* (não usar sintaxe pós-7.4), o
  que também é válido rodando em 7.6.
- Ambiente local (`func start`) continua usando o PowerShell 7.4 instalado na máquina
  (worker do Core Tools) — só a Function App **implantada** na Azure usa 7.6. Se aparecer
  alguma diferença de comportamento entre 7.4 local e 7.6 no Azure, investigar ali.
