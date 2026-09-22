# ADR 0001 — Envio de e-mail

## Contexto

O sistema precisa enviar alertas por e-mail para clientes e um resumo diário para o administrador, sem armazenar segredos de credenciais no repositório ou em configuração de texto plano.

## Decisão

Usar **Azure Communication Services (ACS) Email**, autenticado por **Managed Identity** via REST (sem SDK/módulo dedicado).

## Consequências

- Nenhum segredo de envio de e-mail precisa ser gerenciado manualmente.
- No ambiente `dev`, o domínio de envio é o gerenciado pelo próprio Azure; no `prod`, será usado domínio próprio (com SPF, DKIM e DMARC — ver Marco 0.6 e Piloto).
- Alternativa descartada: Graph API com caixa M365 (exigiria licença M365 e fluxo de autenticação mais complexo para este caso de uso).
