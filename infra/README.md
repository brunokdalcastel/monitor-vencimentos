# Infraestrutura — Terraform

Duas etapas, nessa ordem. A primeira é manual e só roda **uma vez**; a segunda é o que
a esteira do GitHub Actions (T10) usa dali em diante.

## 1. Bootstrap (manual, uma vez)

Cria o Resource Group + Storage Account onde fica o *state* do Terraform, o Resource
Group vazio do ambiente `dev`, e a identidade (App Registration + Service Principal)
que o GitHub Actions usa pra logar na Azure sem segredo (OIDC/federated credentials).

```powershell
az login
cd infra/bootstrap
terraform init
terraform plan
terraform apply
```

Se o nome padrão do Storage Account do state (`stmvenctfstate`) já estiver em uso —
nomes de Storage Account são únicos em **todo o Azure**, não só na sua assinatura —
rode com `-var storage_account_name=<outro-nome>` e ajuste o mesmo nome no
`../backend.tf` antes do passo 2.

Ao final, anote as saídas (`terraform output`):

| Saída | Onde usar |
|---|---|
| `github_actions_client_id` | Variável `AZURE_CLIENT_ID` no repositório GitHub |
| `azure_tenant_id` | Variável `AZURE_TENANT_ID` no repositório GitHub |
| `azure_subscription_id` | Variável `AZURE_SUBSCRIPTION_ID` no repositório GitHub |

(Configuração das variáveis do repositório e do GitHub Environment `dev` — com
aprovação manual pro deploy — é tarefa da T10.)

## 2. Infra principal (`dev`)

Usa o backend criado no bootstrap. Local (com sua conta, via `az login`) ou pela
esteira (com a identidade OIDC criada acima) — o `use_azuread_auth` no `backend.tf`
funciona dos dois jeitos, sem chave de acesso.

```powershell
cd infra
copy pessoal.auto.tfvars.example pessoal.auto.tfvars   # preencha seu e-mail (fica fora do Git)
az provider register --namespace Microsoft.Communication  # 1x por assinatura, se ainda não registrado
terraform init
terraform plan -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars
```

Deploy do código (sem a esteira): monte o pacote com `modules/` dentro (igual ao
passo "Empacotar a Function" do `.github/workflows/deploy.yml`) e rode
`func azure functionapp publish func-mvenc-dev --powershell` de dentro dele.

**Pendências a confirmar no primeiro apply real** (não dava pra verificar sem os
recursos existirem — ver T09 no `PLANO.md`):
- Se `azurerm_email_communication_service_domain` aceita mesmo o nome fixo
  `"AzureManagedDomain"` pro domínio gerenciado pelo Azure.
- Se `from_sender_domain` é o atributo certo pra montar o `ACS_REMETENTE`
  (`DoNotReply@<domínio>`) — ou se é `mail_from_sender_domain`.
- Se o papel **"Communication and Email Service Owner"** (o único papel embutido do
  Azure pra ACS — não existe um mais restrito só pra enviar e-mail) realmente autoriza
  o envio via Entra ID pela identidade gerenciada da Function, já que suas
  `dataActions` vêm vazias na definição do papel (`az role definition list`).

## Destruir tudo (parar de gastar/ocupar cota)

```powershell
cd infra
terraform destroy -var-file=environments/dev.tfvars
```

O bootstrap (state + identidade OIDC) pode ficar de pé — não custa nada relevante
parado, e evita ter que reconfigurar as variáveis do GitHub Actions se você quiser
subir a infra de novo depois.
