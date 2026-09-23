#Requires -Modules Pester

BeforeAll {
    Import-Module "$PSScriptRoot/../src/modules/Dominio/Dominio.psd1" -Force
    $script:FixturesPath = "$PSScriptRoot/fixtures/rdap"
}

Describe 'ConvertTo-DominioNormalizado' {
    It 'remove o esquema https://' {
        ConvertTo-DominioNormalizado -Dominio 'https://exemplo.com' | Should -Be 'exemplo.com'
    }

    It 'remove o esquema http://' {
        ConvertTo-DominioNormalizado -Dominio 'http://exemplo.com' | Should -Be 'exemplo.com'
    }

    It 'remove o prefixo www.' {
        ConvertTo-DominioNormalizado -Dominio 'www.exemplo.com' | Should -Be 'exemplo.com'
    }

    It 'remove esquema e www. juntos' {
        ConvertTo-DominioNormalizado -Dominio 'https://www.exemplo.com' | Should -Be 'exemplo.com'
    }

    It 'remove o caminho' {
        ConvertTo-DominioNormalizado -Dominio 'https://exemplo.com/algum/caminho' | Should -Be 'exemplo.com'
    }

    It 'remove query string' {
        ConvertTo-DominioNormalizado -Dominio 'exemplo.com?a=1' | Should -Be 'exemplo.com'
    }

    It 'converte para minúsculas' {
        ConvertTo-DominioNormalizado -Dominio 'EXEMPLO.COM' | Should -Be 'exemplo.com'
    }

    It 'aceita espaços nas pontas' {
        ConvertTo-DominioNormalizado -Dominio '  exemplo.com  ' | Should -Be 'exemplo.com'
    }

    It 'rejeita domínio vazio' {
        { ConvertTo-DominioNormalizado -Dominio '' } | Should -Throw
    }

    It 'rejeita domínio só com espaços' {
        { ConvertTo-DominioNormalizado -Dominio '   ' } | Should -Throw
    }
}

Describe 'Get-VencimentoDominio' {
    Context 'Domínio .br' {
        BeforeAll {
            $script:FixtureBr = Get-Content "$script:FixturesPath/registro-br-globo.com.br.json" -Raw | ConvertFrom-Json
        }

        It 'usa o RDAP do registro.br e extrai a data de expiração' {
            Mock Invoke-RestMethod -ModuleName Dominio {
                $Uri | Should -Be 'https://rdap.registro.br/domain/globo.com.br'
                return $script:FixtureBr
            }

            $r = Get-VencimentoDominio -Dominio 'globo.com.br'

            $r.Status | Should -Be 'Ok'
            $r.Fonte | Should -Be 'registro.br'
            $r.DataExpiracao | Should -BeOfType [datetime]
            $r.DataExpiracao.Year | Should -Be 2029
            $r.Erro | Should -BeNullOrEmpty
            Should -Invoke Invoke-RestMethod -ModuleName Dominio -Times 1 -Exactly
        }
    }

    Context 'Domínio não-.br' {
        BeforeAll {
            $script:FixtureCom = Get-Content "$script:FixturesPath/rdap-org-google.com.json" -Raw | ConvertFrom-Json
        }

        It 'usa o RDAP bootstrap (rdap.org) e extrai a data de expiração' {
            Mock Invoke-RestMethod -ModuleName Dominio {
                $Uri | Should -Be 'https://rdap.org/domain/google.com'
                return $script:FixtureCom
            }

            $r = Get-VencimentoDominio -Dominio 'https://www.google.com/busca'

            $r.Status | Should -Be 'Ok'
            $r.Fonte | Should -Be 'rdap.org'
            $r.DataExpiracao | Should -BeOfType [datetime]
            $r.DataExpiracao.Year | Should -Be 2028
        }
    }

    Context 'Domínio inexistente (404)' {
        It 'reporta Status NaoEncontrado sem lançar exceção' {
            Mock Invoke-RestMethod -ModuleName Dominio { throw 'Response status code does not indicate success: 404 (Not Found).' }

            $r = Get-VencimentoDominio -Dominio 'definitelydoesnotexist987654321.org'

            $r.Status | Should -Be 'NaoEncontrado'
            $r.DataExpiracao | Should -BeNullOrEmpty
            $r.Erro | Should -BeNullOrEmpty
        }
    }

    Context 'Rate limit (429)' {
        It 'tenta novamente uma vez e obtém sucesso na segunda tentativa' {
            $script:FixtureCom = Get-Content "$script:FixturesPath/rdap-org-google.com.json" -Raw | ConvertFrom-Json
            $script:chamada = 0
            Mock Invoke-RestMethod -ModuleName Dominio {
                $script:chamada++
                if ($script:chamada -eq 1) {
                    throw 'Response status code does not indicate success: 429 (Too Many Requests).'
                }
                return $script:FixtureCom
            }

            $r = Get-VencimentoDominio -Dominio 'google.com' -EsperaRetentativaMs 0

            $r.Status | Should -Be 'Ok'
            Should -Invoke Invoke-RestMethod -ModuleName Dominio -Times 2 -Exactly
        }

        It 'reporta Erro se a segunda tentativa também falhar com 429' {
            Mock Invoke-RestMethod -ModuleName Dominio { throw 'Response status code does not indicate success: 429 (Too Many Requests).' }

            $r = Get-VencimentoDominio -Dominio 'google.com' -EsperaRetentativaMs 0

            $r.Status | Should -Be 'Erro'
            $r.Erro | Should -Not -BeNullOrEmpty
            Should -Invoke Invoke-RestMethod -ModuleName Dominio -Times 2 -Exactly
        }
    }

    Context 'Timeout / erro genérico' {
        It 'reporta Erro sem lançar exceção' {
            Mock Invoke-RestMethod -ModuleName Dominio { throw 'Tempo de operação esgotado.' }

            $r = Get-VencimentoDominio -Dominio 'exemplo.com'

            $r.Status | Should -Be 'Erro'
            $r.Erro | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Resposta sem evento de expiração' {
        It 'reporta Erro' {
            Mock Invoke-RestMethod -ModuleName Dominio { return [pscustomobject] @{ events = @() } }

            $r = Get-VencimentoDominio -Dominio 'exemplo.com'

            $r.Status | Should -Be 'Erro'
            $r.Erro | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Entrada inválida' {
        It 'reporta Erro para domínio vazio, sem lançar exceção' {
            $r = Get-VencimentoDominio -Dominio '   '

            $r.Status | Should -Be 'Erro'
            $r.Erro | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Get-VencimentoDominio (integração real)' -Tag 'Integration' {
    It 'consulta o RDAP real do registro.br (.br) e retorna uma data de expiração futura' {
        $r = Get-VencimentoDominio -Dominio 'globo.com.br'

        $r.Erro | Should -BeNullOrEmpty
        $r.Status | Should -Be 'Ok'
        $r.Fonte | Should -Be 'registro.br'
        $r.DataExpiracao | Should -BeGreaterThan (Get-Date).ToUniversalTime()
    }

    It 'consulta o RDAP real via bootstrap (rdap.org) e retorna uma data de expiração futura' {
        $r = Get-VencimentoDominio -Dominio 'google.com'

        $r.Erro | Should -BeNullOrEmpty
        $r.Status | Should -Be 'Ok'
        $r.Fonte | Should -Be 'rdap.org'
        $r.DataExpiracao | Should -BeGreaterThan (Get-Date).ToUniversalTime()
    }

    It 'reporta NaoEncontrado para um domínio .br inexistente' {
        $r = Get-VencimentoDominio -Dominio 'dominioinexistentexyz123456789.br'

        $r.Status | Should -Be 'NaoEncontrado'
    }
}
