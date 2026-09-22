# ADR 0010 — Cadastro de itens A3/Manual no MVP

## Contexto

Certificados A3 e itens manuais (sem verificação automática) precisam ter sua `DataVencimento` cadastrada por alguém, mas o portal web só está planejado para a Fase 3.

## Decisão

No MVP (Fase 1), o cadastro é feito via **CSV + script** (`tools/Import-Itens.ps1`), que lê um arquivo CSV com as colunas da tabela `Itens`, valida com `ConvertTo-ItemNormalizado` e faz upsert no Table Storage.

## Consequências

- Não é necessário construir um portal antes de validar o produto com o piloto.
- O cadastro/atualização de itens depende de rodar o script manualmente (aceitável para o volume do piloto, poucos clientes).
- O portal (Fase 3) poderá reaproveitar a mesma função de validação (`ConvertTo-ItemNormalizado`) por trás de uma API.
