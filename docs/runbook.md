# Runbook

Operações do dia a dia do Monitor de Vencimentos, em `dev` (único ambiente — ver
[ADR 0013](decisoes/0013-escopo-pessoal-sem-piloto.md)). Para subir/derrubar a infra,
ver [`infra/README.md`](../infra/README.md). Para rodar localmente, ver o
[`README.md`](../README.md) principal.

## Cadastrar um item

**Local (Azurite):**

```powershell
# edite tools/itens-exemplo.csv (ou crie outro CSV com as mesmas colunas) e rode:
./tools/Import-Itens.ps1 -CaminhoCsv ./tools/itens-exemplo.csv
```

**No ambiente `dev` implantado:** mesma coisa, apontando as variáveis de ambiente do
módulo Storage pro Storage Account real em vez do Azurite (o `Import-Itens.ps1` não
faz distinção — só depende de `TABELAS_ENDPOINT`/`TABELAS_MODO_AUTH` etc. já
configurados no ambiente de onde você roda):

```powershell
$env:TABELAS_ENDPOINT  = 'https://<storage-account>.table.core.windows.net'
$env:TABELAS_MODO_AUTH = 'ManagedIdentity'   # exige IDENTITY_ENDPOINT/IDENTITY_HEADER — só funciona
                                               # rodando de dentro da própria Function (ver limitação abaixo)
./tools/Import-Itens.ps1 -CaminhoCsv <arquivo>
```

> **Limitação conhecida:** como o Storage não aceita chave de acesso
> (`shared_access_key_enabled = false`, D3), só dá pra escrever no Storage Account real
> com uma identidade autorizada — hoje só a própria Function tem isso (via Managed
> Identity). Não existe hoje um jeito direto de rodar `Import-Itens.ps1` da sua máquina
> local contra o Storage de `dev`. Alternativas: (1) usar o portal do Azure / Azure
> Storage Explorer, autenticado com sua própria conta (que já tem `Contributor` no RG,
> mas precisaria também de `Storage Table Data Contributor` — dar esse papel pra si
> mesmo se precisar); (2) melhoria futura: um script que roda via `az rest`/Storage
> Explorer com sua identidade Entra ID em vez da Managed Identity da Function.

**Colunas do CSV** (mesmas da tabela `Itens` — ver [`docs/especificacao.md`](especificacao.md) seção 4):

| Coluna | Obrigatório | Exemplo |
|---|---|---|
| `ClienteId` | sim | `cliente1` |
| `ItemId` | sim | `item-ssl-1` |
| `Tipo` | sim | `SSL`, `Dominio`, `CertA3`, `Manual` (`CertA1` só na Fase 2) |
| `Alvo` | sim | `www.exemplo.com`, `exemplo.com.br`, descrição livre pra `Manual`/`CertA3` |
| `Descricao`, `Titular` | não | texto livre |
| `DataVencimento` | só p/ `CertA3`/`Manual` | `2026-12-15` (`yyyy-MM-dd`) |
| `ContatosAlerta` | sim | `a@x.com;b@x.com` (`;` separa vários) |
| `Ativo` | não (padrão `true`) | `true`/`false` |

## Reprocessar a verificação de hoje

Já suportado e idempotente (rodar de novo não duplica nada — ver D8/T07): dispare a
Function manualmente pela API administrativa do runtime.

```powershell
curl -X POST https://<function-app>.azurewebsites.net/admin/functions/VerificacaoDiaria `
  -H "Content-Type: application/json" -H "x-functions-key: <chave-do-admin>" -d '{}'
```

(A chave (`x-functions-key`) vem de **Function App → App keys** no portal, ou
`az functionapp keys list`. Localmente, sem `func start` pedindo chave, é só o `curl`
sem o header — ver README.)

## Reprocessar um dia passado

**Não tem suporte direto hoje** — `run.ps1` sempre chama `Invoke-VerificacaoDiaria`
sem `-Hoje`, então ela usa sempre a data de hoje (`Get-DataHojeBrasil`). Não existe um
jeito limpo de mandar uma data diferente pela API HTTP administrativa.

Workarounds, nenhum ideal:
- **SSH/Kudu na Function App** (`az webapp ssh -g <rg> -n <function-app>`) e rodar
  `Invoke-VerificacaoDiaria -Hoje '2026-09-20'` manualmente de dentro do ambiente — só
  ali a Managed Identity está disponível. **Não confirmado** se o Flex Consumption
  expõe SSH/console interativo (é um modelo de hospedagem mais novo que o App Service
  clássico) — pode não funcionar.
- **Melhoria futura recomendada**: adicionar um parâmetro opcional de data na função
  (ex.: uma Function HTTP separada, só-admin, que aceita `?data=2026-09-20` e chama
  `Invoke-VerificacaoDiaria -Hoje $data`), já que `Invoke-VerificacaoDiaria` (T07) já
  aceita `-Hoje` — falta só expor isso por fora.

## Trocar o contato de um item

Reimporte o mesmo `ItemId` com o `ContatosAlerta` atualizado — `Set-Entidade` é upsert
(`InsertOrReplace`), então substitui a linha inteira:

```powershell
# no CSV, ache a linha do ItemId e troque ContatosAlerta, depois:
./tools/Import-Itens.ps1 -CaminhoCsv <arquivo-com-a-linha-atualizada>
```

Cuidado: por ser `InsertOrReplace` (não merge), a linha do CSV precisa ter **todas** as
colunas do item (não só `ContatosAlerta`), senão os outros campos somem.

## Desativar (ou remover) um item

- **Desativar** (recomendado — mantém o histórico): coloque `Ativo=false` na linha do
  CSV e reimporte. O item para de ser verificado e de gerar alerta, mas continua
  existindo pra referência.
- **Remover de vez**: via Azure Storage Explorer / portal, apague a entidade da tabela
  `Itens` (PartitionKey=`ClienteId`, RowKey=`ItemId`). Não há hoje um script pra isso
  (só upsert, sem "Remove-Item" nos `tools/`).

## Investigar uma falha (Application Insights)

1. Portal do Azure → Function App → **Application Insights** (ou direto no recurso
   `appi-mvenc-dev`) → **Transaction search** ou **Logs**.
2. Consulta KQL pra ver as últimas execuções com problema:
   ```kusto
   traces
   | where message has "Falha"
   | order by timestamp desc
   | take 50
   ```
   ou, pra ver tudo que a Function logou numa execução específica (`run.ps1` usa
   `Write-Information`/`Write-Warning` — ver T08):
   ```kusto
   traces
   | where operation_Name == "VerificacaoDiaria"
   | order by timestamp desc
   | take 100
   ```
3. Falhas de *verificação* de um item específico (não da Function em si) ficam na
   tabela `Verificacoes` (`Sucesso=false`, campo `Erro`) — mais rápido de consultar ali
   direto do que no App Insights, se for isso que você quer (ver Storage Explorer).
4. **3 falhas seguidas do mesmo item** já viram um aviso destacado no e-mail de resumo
   diário do admin (ver T07/`Get-ContagemFalhasConsecutivas`) — normalmente é ali que
   você vai notar primeiro, antes de precisar ir no App Insights.
5. Alerta automático: `alert-mvenc-function-failures-dev` (Azure Monitor, ver T09)
   dispara e-mail pro `ADMIN_EMAIL` quando a métrica `FunctionExecutionCount` registra
   pelo menos uma falha na última hora.

## Rotacionar configurações (app settings)

**Preferencial — via Terraform** (evita a próxima `terraform apply` desfazer uma
mudança feita só no portal): edite `infra/environments/dev.tfvars` (ex.: `admin_email`)
ou `infra/function.tf` (o bloco `app_settings`), depois:

```powershell
cd infra
terraform apply -var-file=environments/dev.tfvars
```

**Rápido/emergencial — via CLI** (drift até o próximo `apply`, que sobrescreve de
volta pro que está no `.tf`):

```powershell
az functionapp config appsettings set -g rg-mvenc-dev -n <function-app> `
  --settings ADMIN_EMAIL=novo-admin@exemplo.com
```

Variáveis que fazem sentido rotacionar: `ADMIN_EMAIL`, `EMAIL_MODO` (`Envio` ↔
`Arquivo`, útil pra "pausar" o envio real sem derrubar a Function).
