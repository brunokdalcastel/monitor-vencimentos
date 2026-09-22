# ADR 0006 — Horário de execução

## Contexto

O plano Flex Consumption em Linux não suporta a variável `WEBSITE_TIME_ZONE`, então o timer trigger só pode ser expresso em UTC, mas os cálculos de dias restantes precisam refletir o fuso do Brasil.

## Decisão

Timer trigger `0 0 11 * * *` (UTC), equivalente a **08:00 BRT**. Todo cálculo de "hoje"/dias restantes é feito explicitamente no fuso `America/Sao_Paulo` dentro do código, independentemente do fuso do host.

## Consequências

- A expressão cron do timer não muda com o horário de verão (o Brasil não usa mais horário de verão), mas precisa ser revisada se a regra mudar.
- Toda a lógica de datas (`Get-DataHojeBrasil`, T02) converte explicitamente para `America/Sao_Paulo`, nunca confiando no fuso do host da Function.
