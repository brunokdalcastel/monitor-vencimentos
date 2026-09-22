# ADR 0012 — Verificação de domínios não-`.br`

## Contexto

O RDAP do Registro.br cobre apenas domínios `.br`. O público-alvo (MSPs, escritórios, pequenas empresas) também tem domínios `.com`, `.com.br` é coberto pelo Registro.br, mas outros TLDs genéricos precisam de outra fonte.

## Decisão

- Domínios `.br` → `https://rdap.registro.br/domain/<dominio>` (direto).
- Demais domínios → bootstrap IANA via `https://rdap.org/domain/<dominio>`, que redireciona para o servidor RDAP correto do TLD.

## Consequências

- Cobre a maioria dos TLDs sem precisar de uma lista própria de servidores RDAP por TLD.
- Depende da disponibilidade do serviço público `rdap.org` para domínios não-`.br`; falhas de consulta entram no tratamento de erro padrão (não geram alerta ao cliente, vão para o resumo do admin — ver regra de marcos em `PLANO.md`).
