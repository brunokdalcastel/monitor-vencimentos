#Requires -Modules Pester
# Testes de integração do módulo Storage contra o Azurite local.
# Pré-requisito: Azurite com o serviço de tabelas rodando, ex.:
#   azurite --location .azurite --silent
#   (ou só tabelas: azurite-table --location .azurite --silent)
# A chave usada é a chave pública e conhecida do emulador — não é segredo de produção.

BeforeAll {
    Import-Module "$PSScriptRoot/../../src/modules/Storage/Storage.psd1" -Force

    $env:TABELAS_ENDPOINT = 'http://127.0.0.1:10002/devstoreaccount1'
    $env:TABELAS_MODO_AUTH = 'SharedKey'
    $env:TABELAS_CONTA = 'devstoreaccount1'
    $env:TABELAS_CHAVE = 'Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw=='

    $script:Tabela = "TesteIntegracao$([guid]::NewGuid().ToString('N').Substring(0, 8))"
}

Describe 'Storage — CRUD completo contra o Azurite' -Tag 'Integration' {
    It 'cria a tabela, e criar de novo é idempotente' {
        { New-TabelaSeNaoExistir -Tabela $script:Tabela } | Should -Not -Throw
        { New-TabelaSeNaoExistir -Tabela $script:Tabela } | Should -Not -Throw
    }

    It 'insere (upsert) uma entidade e consulta de volta' {
        Set-Entidade -Tabela $script:Tabela -Entidade @{
            PartitionKey = 'cliente1'
            RowKey       = 'item1'
            Nome         = "O'Brien & Associados"
            Ativo        = $true
        }

        $r = Get-Entidades -Tabela $script:Tabela -Filtro "PartitionKey eq 'cliente1' and RowKey eq 'item1'"

        $r.Count | Should -Be 1
        $r[0].Nome | Should -Be "O'Brien & Associados"
        $r[0].Ativo | Should -Be $true
    }

    It 'substitui a entidade inteira em um novo upsert (InsertOrReplace)' {
        Set-Entidade -Tabela $script:Tabela -Entidade @{
            PartitionKey = 'cliente1'
            RowKey       = 'item1'
            Nome         = 'Nome Atualizado'
        }

        $r = Get-Entidades -Tabela $script:Tabela -Filtro "PartitionKey eq 'cliente1' and RowKey eq 'item1'"

        $r.Count | Should -Be 1
        $r[0].Nome | Should -Be 'Nome Atualizado'
        $r[0].PSObject.Properties.Match('Ativo').Count | Should -Be 0
    }

    It 'pagina automaticamente quando há várias entidades na mesma partição' {
        1..5 | ForEach-Object {
            Set-Entidade -Tabela $script:Tabela -Entidade @{
                PartitionKey = 'paginacao'
                RowKey       = "item$_"
            }
        }

        $r = Get-Entidades -Tabela $script:Tabela -Filtro "PartitionKey eq 'paginacao'"

        $r.Count | Should -Be 5
    }

    It 'escapa aspas simples em PartitionKey/RowKey' {
        Set-Entidade -Tabela $script:Tabela -Entidade @{
            PartitionKey = "cliente'especial"
            RowKey       = 'item1'
        }

        $filtro = "PartitionKey eq '$(ConvertTo-ValorFiltroOData "cliente'especial")' and RowKey eq 'item1'"
        $r = Get-Entidades -Tabela $script:Tabela -Filtro $filtro

        $r.Count | Should -Be 1

        Remove-Entidade -Tabela $script:Tabela -PartitionKey "cliente'especial" -RowKey 'item1'
    }

    It 'remove uma entidade' {
        Remove-Entidade -Tabela $script:Tabela -PartitionKey 'cliente1' -RowKey 'item1'

        $r = Get-Entidades -Tabela $script:Tabela -Filtro "PartitionKey eq 'cliente1' and RowKey eq 'item1'"

        $r.Count | Should -Be 0
    }
}
