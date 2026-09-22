# ADR 0008 — Deduplicação de alertas

## Contexto

A verificação diária pode rodar mais de uma vez no mesmo dia (reprocessamento manual, retry) e não deve reenviar um alerta já disparado para o mesmo marco. Por outro lado, a renovação de um item (nova `DataVencimento`) deve reiniciar o ciclo de alertas.

## Decisão

A chave de deduplicação na tabela `AlertasEnviados` é a combinação **`ItemId` + `DataVencimento` + `Marco`**.

## Consequências

- Rodar a verificação duas vezes no mesmo dia não duplica alertas (idempotência, ver critério de aceite da T07).
- Quando um item é renovado, a `DataVencimento` muda, o que naturalmente gera uma nova chave e libera o ciclo de alertas (30 → 15 → 7 → 0) sem precisar de lógica extra de "reset".
- Itens `VENCIDO` usam uma variação da chave com número da semana (`VENCIDO-n`) — ver [ADR 0009](0009-item-vencido.md).
