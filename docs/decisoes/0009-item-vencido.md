# ADR 0009 — Repetição de alerta para item vencido

## Contexto

Um item vencido e não renovado (`Ativo=true`) não deve gerar um alerta único e depois ser esquecido — o risco para o cliente continua enquanto o item não é resolvido.

## Decisão

Disparar o marco `VENCIDO` no dia 0 (vencimento) e **repetir o alerta a cada 7 dias** enquanto o item continuar `Ativo=true` e vencido.

## Consequências

- A chave em `AlertasEnviados` para esse caso é `ItemId` + `DataVencimento` + `VENCIDO-n`, onde `n = floor(|DiasRestantes| / 7)` (ver [ADR 0008](0008-deduplicacao-de-alertas.md)), o que naturalmente gera uma nova entrada a cada semana.
- Evita que um item vencido fique "esquecido" após o primeiro alerta.
- Se o cliente quiser parar de receber alertas de um item vencido que não será renovado, precisa marcá-lo como `Ativo=false`.
