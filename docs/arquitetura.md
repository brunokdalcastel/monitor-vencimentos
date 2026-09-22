# Arquitetura

> Diagrama e componentes copiados da seção 3 de [`especificacao.md`](especificacao.md). Decisões de projeto associadas estão em [`decisoes/`](decisoes/) (ADRs 0001–0012).

## Visão geral

```
[Timer diário] → Azure Function (PowerShell)
                    ├─ lê inventário ........ Table Storage
                    ├─ checa SSL ............ conexão TLS 443
                    ├─ checa domínio ........ RDAP Registro.br
                    ├─ grava resultado ...... Table Storage
                    └─ envia alertas ........ E-mail (ACS Email ou Graph API)

[Agente A1 no cliente] → Function HTTP (chave de API) → Table Storage   (fase 2)
[Portal do cliente]    → Static Web Apps → API → Table Storage          (fase 3)
```

## Componentes

| Recurso | Uso | Observação |
|---|---|---|
| Resource Group | Agrupar tudo | Um por ambiente (dev/prod) |
| Storage Account | Table Storage (inventário, resultados, log) + armazenamento da Function | Custo de centavos |
| Function App (Flex Consumption) | Verificações e API | PowerShell 7.4, Linux — ver [ADR 0004](decisoes/0004-plano-da-function.md) |
| Key Vault | Segredos (chaves de API, credenciais de envio de e-mail) | Function acessa via Managed Identity |
| Azure Communication Services — Email | Envio de alertas | Ver [ADR 0001](decisoes/0001-envio-de-email.md) |
| Application Insights | Logs e falhas | Limite diário de ingestão para não gerar custo |
| Static Web Apps (fase 3) | Portal do cliente | Plano gratuito para começar |

## Fluxo de dados

1. Timer trigger (`VerificacaoDiaria`, ver [ADR 0006](decisoes/0006-horario.md)) dispara diariamente às 08:00 BRT.
2. O orquestrador (T07) lê os itens ativos da tabela `Itens`.
3. Cada item é verificado conforme o `Tipo` (SSL, Dominio, CertA3/Manual, CertA1 — fase 2).
4. O resultado é gravado na tabela `Verificacoes`.
5. O marco de alerta devido é calculado (ver regra de marcos em `PLANO.md`) e, se pendente, um e-mail consolidado é enviado por contato.
6. O envio é registrado na tabela `AlertasEnviados` somente após sucesso.
7. Um resumo diário é enviado ao administrador.

## Autenticação e acesso a dados

- Produção: Managed Identity da Function App, sem segredos em texto.
- Local: SharedKey contra Azurite (ver [ADR 0003](decisoes/0003-autenticacao.md)).
- Acesso ao Table Storage via `Invoke-RestMethod` (sem módulos Az/AzTable — ver [ADR 0002](decisoes/0002-acesso-ao-table-storage.md)), pois o Flex Consumption não suporta managed dependencies.

## Infraestrutura como código

Todo o provisionamento é feito via Terraform (`infra/`), com o `state` em uma Storage Account separada (bootstrap manual único) e deploy contínuo via GitHub Actions com OIDC (ver [ADR 0011](decisoes/0011-iac-ci.md)).
