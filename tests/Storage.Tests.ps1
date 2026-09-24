#Requires -Modules Pester

BeforeAll {
    Import-Module "$PSScriptRoot/../src/modules/Storage/Storage.psd1" -Force
}

Describe 'ConvertTo-ValorFiltroOData' {
    It 'escapa aspas simples dobrando' {
        ConvertTo-ValorFiltroOData -Valor "O'Brien" | Should -Be "O''Brien"
    }

    It 'não altera texto sem aspas' {
        ConvertTo-ValorFiltroOData -Valor 'item-1' | Should -Be 'item-1'
    }

    It 'aceita string vazia' {
        ConvertTo-ValorFiltroOData -Valor '' | Should -Be ''
    }

    It 'escapa múltiplas aspas' {
        ConvertTo-ValorFiltroOData -Valor "a'b'c" | Should -Be "a''b''c"
    }
}

Describe 'New-CabecalhoTabela' {
    BeforeEach {
        $script:backupEnv = @{
            TABELAS_ENDPOINT  = $env:TABELAS_ENDPOINT
            TABELAS_MODO_AUTH = $env:TABELAS_MODO_AUTH
            TABELAS_CONTA     = $env:TABELAS_CONTA
            TABELAS_CHAVE     = $env:TABELAS_CHAVE
        }
    }

    AfterEach {
        $env:TABELAS_ENDPOINT = $script:backupEnv.TABELAS_ENDPOINT
        $env:TABELAS_MODO_AUTH = $script:backupEnv.TABELAS_MODO_AUTH
        $env:TABELAS_CONTA = $script:backupEnv.TABELAS_CONTA
        $env:TABELAS_CHAVE = $script:backupEnv.TABELAS_CHAVE
    }

    Context 'Modo SharedKey (Azurite local)' {
        BeforeEach {
            $env:TABELAS_ENDPOINT = 'http://127.0.0.1:10002/devstoreaccount1'
            $env:TABELAS_MODO_AUTH = 'SharedKey'
            $env:TABELAS_CONTA = 'devstoreaccount1'
            $env:TABELAS_CHAVE = 'Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw=='
        }

        It 'monta Authorization SharedKeyLite com a conta' {
            $h = New-CabecalhoTabela -CaminhoRecurso 'Tables'
            $h['Authorization'] | Should -Match '^SharedKeyLite devstoreaccount1:'
            $h['x-ms-version'] | Should -Not -BeNullOrEmpty
            $h['Accept'] | Should -Be 'application/json;odata=nometadata'
        }

        It 'inclui Content-Type só quando -ComCorpo' {
            $semCorpo = New-CabecalhoTabela -CaminhoRecurso 'Tables'
            $comCorpo = New-CabecalhoTabela -CaminhoRecurso 'Tables' -ComCorpo

            $semCorpo.ContainsKey('Content-Type') | Should -Be $false
            $comCorpo['Content-Type'] | Should -Be 'application/json'
        }

        It 'gera assinaturas diferentes para recursos diferentes' {
            $h1 = New-CabecalhoTabela -CaminhoRecurso 'TabelaA'
            $h2 = New-CabecalhoTabela -CaminhoRecurso 'TabelaB'

            $h1['Authorization'] | Should -Not -Be $h2['Authorization']
        }

        It 'lança erro sem TABELAS_CONTA' {
            $env:TABELAS_CONTA = $null
            { New-CabecalhoTabela -CaminhoRecurso 'Tables' } | Should -Throw
        }

        It 'lança erro sem TABELAS_CHAVE' {
            $env:TABELAS_CHAVE = $null
            { New-CabecalhoTabela -CaminhoRecurso 'Tables' } | Should -Throw
        }
    }

    Context 'Modo ManagedIdentity' {
        BeforeEach {
            $env:TABELAS_ENDPOINT = 'https://minhaconta.table.core.windows.net'
            $env:TABELAS_MODO_AUTH = 'ManagedIdentity'
            $env:TABELAS_CONTA = $null
            $env:TABELAS_CHAVE = $null
        }

        It 'usa o token da Managed Identity como Bearer' {
            Mock Get-TokenAcesso -ModuleName Storage { return 'token-mi-123' }

            $h = New-CabecalhoTabela -CaminhoRecurso 'Tables'

            $h['Authorization'] | Should -Be 'Bearer token-mi-123'
            Should -Invoke Get-TokenAcesso -ModuleName Storage -Times 1 -Exactly -ParameterFilter { $Recurso -eq 'https://storage.azure.com' }
        }
    }

    Context 'Configuração inválida' {
        It 'lança erro sem TABELAS_ENDPOINT' {
            $env:TABELAS_ENDPOINT = $null
            $env:TABELAS_MODO_AUTH = 'SharedKey'
            { New-CabecalhoTabela -CaminhoRecurso 'Tables' } | Should -Throw
        }

        It 'lança erro com TABELAS_MODO_AUTH desconhecido' {
            $env:TABELAS_ENDPOINT = 'http://127.0.0.1:10002/devstoreaccount1'
            $env:TABELAS_MODO_AUTH = 'Outro'
            { New-CabecalhoTabela -CaminhoRecurso 'Tables' } | Should -Throw
        }
    }
}

Describe 'Operações de entidade (Invoke-WebRequest mockado)' {
    BeforeAll {
        $env:TABELAS_ENDPOINT = 'http://127.0.0.1:10002/devstoreaccount1'
        $env:TABELAS_MODO_AUTH = 'SharedKey'
        $env:TABELAS_CONTA = 'devstoreaccount1'
        $env:TABELAS_CHAVE = 'Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw=='
    }

    Context 'New-TabelaSeNaoExistir' {
        It 'faz POST em /Tables com o nome da tabela' {
            Mock Invoke-WebRequest -ModuleName Storage {
                $Uri | Should -Be 'http://127.0.0.1:10002/devstoreaccount1/Tables'
                $Method | Should -Be 'POST'
                $Body | Should -Match '"TableName":\s*"Itens"'
                return [pscustomobject] @{ StatusCode = 201; Content = '{"TableName":"Itens"}'; Headers = @{} }
            }

            { New-TabelaSeNaoExistir -Tabela 'Itens' } | Should -Not -Throw
        }

        It 'não lança erro quando a tabela já existe (409)' {
            Mock Invoke-WebRequest -ModuleName Storage {
                throw [System.Net.WebException]::new('The remote server returned an error: (409) Conflict.')
            }

            { New-TabelaSeNaoExistir -Tabela 'Itens' } | Should -Not -Throw
        }

        It 'propaga outros erros' {
            Mock Invoke-WebRequest -ModuleName Storage { throw 'Erro de rede qualquer' }

            { New-TabelaSeNaoExistir -Tabela 'Itens' } | Should -Throw
        }
    }

    Context 'Set-Entidade' {
        It 'monta o caminho com PartitionKey/RowKey escapados e faz PUT' {
            Mock Invoke-WebRequest -ModuleName Storage {
                $Uri | Should -Be "http://127.0.0.1:10002/devstoreaccount1/Itens(PartitionKey='p1',RowKey='r''1')"
                $Method | Should -Be 'PUT'
                return [pscustomobject] @{ StatusCode = 204; Content = ''; Headers = @{} }
            }

            { Set-Entidade -Tabela 'Itens' -Entidade @{ PartitionKey = 'p1'; RowKey = "r'1" } } | Should -Not -Throw
        }

        It 'exige PartitionKey e RowKey' {
            { Set-Entidade -Tabela 'Itens' -Entidade @{ PartitionKey = 'p1' } } | Should -Throw
        }

        It 'aceita a entidade como pscustomobject' {
            Mock Invoke-WebRequest -ModuleName Storage {
                return [pscustomobject] @{ StatusCode = 204; Content = ''; Headers = @{} }
            }

            $entidade = [pscustomobject] @{ PartitionKey = 'p1'; RowKey = 'r1' }
            { Set-Entidade -Tabela 'Itens' -Entidade $entidade } | Should -Not -Throw
        }
    }

    Context 'Remove-Entidade' {
        It 'faz DELETE com If-Match: *' {
            Mock Invoke-WebRequest -ModuleName Storage {
                $Method | Should -Be 'DELETE'
                $Headers['If-Match'] | Should -Be '*'
                $Uri | Should -Be "http://127.0.0.1:10002/devstoreaccount1/Itens(PartitionKey='p1',RowKey='r1')"
                return [pscustomobject] @{ StatusCode = 204; Content = ''; Headers = @{} }
            }

            { Remove-Entidade -Tabela 'Itens' -PartitionKey 'p1' -RowKey 'r1' } | Should -Not -Throw
        }
    }

    Context 'Get-Entidades' {
        It 'url-encoda o filtro' {
            # Observação: Invoke-WebRequest recebe -Uri como [uri]; a normalização desse
            # tipo difere entre .NET Framework (Windows PowerShell 5.1) e .NET moderno
            # (7.x) — o Framework trata a aspa simples como "segura" e desfaz o %27 de
            # volta para ' mesmo em .AbsoluteUri (mas a requisição real sai igual nos
            # dois, confirmado contra o Azurite real no teste de integração). Por isso o
            # teste aceita a aspa escapada ou não; o espaço (%20) já é estável nos dois.
            Mock Invoke-WebRequest -ModuleName Storage {
                $Uri.AbsoluteUri | Should -Match '\$filter=PartitionKey%20eq%20(%27|'')p1(%27|'')'
                return [pscustomobject] @{ StatusCode = 200; Content = '{"value":[]}'; Headers = @{} }
            }

            Get-Entidades -Tabela 'Itens' -Filtro "PartitionKey eq 'p1'" | Out-Null
        }

        It 'pagina automaticamente seguindo x-ms-continuation-*' {
            $script:chamada = 0
            Mock Invoke-WebRequest -ModuleName Storage {
                $script:chamada++
                if ($script:chamada -eq 1) {
                    $Uri | Should -Not -Match 'NextPartitionKey'
                    return [pscustomobject] @{
                        StatusCode = 200
                        Content    = '{"value":[{"PartitionKey":"p1","RowKey":"r1"}]}'
                        Headers    = @{ 'x-ms-continuation-NextPartitionKey' = 'p1'; 'x-ms-continuation-NextRowKey' = 'r2' }
                    }
                }
                $Uri | Should -Match 'NextPartitionKey=p1'
                $Uri | Should -Match 'NextRowKey=r2'
                return [pscustomobject] @{
                    StatusCode = 200
                    Content    = '{"value":[{"PartitionKey":"p1","RowKey":"r2"}]}'
                    Headers    = @{}
                }
            }

            $resultado = Get-Entidades -Tabela 'Itens'

            $resultado.Count | Should -Be 2
            Should -Invoke Invoke-WebRequest -ModuleName Storage -Times 2 -Exactly
        }

        It 'devolve array vazio quando não há entidades' {
            Mock Invoke-WebRequest -ModuleName Storage {
                return [pscustomobject] @{ StatusCode = 200; Content = '{"value":[]}'; Headers = @{} }
            }

            $resultado = Get-Entidades -Tabela 'Itens'
            $resultado.Count | Should -Be 0
        }

        It 'inclui $select quando informado' {
            Mock Invoke-WebRequest -ModuleName Storage {
                $Uri.AbsoluteUri | Should -Match ([regex]::Escape('$select=PartitionKey%2CRowKey'))
                return [pscustomobject] @{ StatusCode = 200; Content = '{"value":[]}'; Headers = @{} }
            }

            Get-Entidades -Tabela 'Itens' -Select 'PartitionKey,RowKey' | Out-Null
        }
    }
}
