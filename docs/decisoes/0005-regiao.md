# ADR 0005 — Região do Azure

## Contexto

É preciso escolher a região Azure onde os recursos serão provisionados, equilibrando custo, latência e o argumento comercial de manter dados de clientes brasileiros no Brasil.

## Decisão

Usar **Brazil South** como região principal.

## Consequências

- Reforça o argumento de venda "dados no Brasil" para o público-alvo (cartórios, contabilidades, pequenas empresas brasileiras).
- A disponibilidade do plano Flex Consumption com PowerShell 7.4 nessa região precisa ser confirmada na T09.
- **Fallback:** caso não esteja disponível, usar **East US 2**.
