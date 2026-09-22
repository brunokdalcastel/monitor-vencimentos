# ADR 0007 — Agrupamento de alertas por contato

## Contexto

Um mesmo contato pode ter vários itens (domínios, certificados) atingindo marcos de alerta no mesmo dia. Enviar um e-mail por item geraria ruído desnecessário.

## Decisão

Enviar **um único e-mail consolidado por contato por dia**, agrupando todos os itens que atingiram um marco naquele dia (ordenados por urgência: vencidos → 0 → 7 → 15 → 30).

## Consequências

- Menos ruído para o cliente final e menor custo de envio.
- A lógica de agrupamento (T07) precisa juntar os itens por `ContatosAlerta` antes de montar o e-mail (T06 — `New-EmailAlerta`).
- O registro em `AlertasEnviados` continua sendo por item + marco, não por e-mail enviado.
