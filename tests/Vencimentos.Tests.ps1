#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }
# Testes unitários do módulo Vencimentos (T02) — regras puras, sem rede.
# Variáveis criadas em BeforeAll são usadas nos blocos It; o analisador não enxerga esse escopo do Pester.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Escopo BeforeAll/It do Pester.')]
param()

BeforeAll {
    $caminhoModulo = Join-Path $PSScriptRoot '..\src\modules\Vencimentos\Vencimentos.psd1'
    Import-Module $caminhoModulo -Force
}

AfterAll {
    Remove-Module Vencimentos -ErrorAction SilentlyContinue
}

Describe 'Get-DataHojeBrasil' {
    It 'retorna a mesma data quando o horário em BRT ainda é do mesmo dia' {
        $agora = [datetime]::new(2026, 9, 22, 15, 0, 0, [DateTimeKind]::Utc)   # 12:00 BRT
        Get-DataHojeBrasil -Agora $agora | Should -Be ([datetime]'2026-09-22')
    }

    It 'virada de fuso: 23:30 BRT (02:30 UTC do dia seguinte) ainda é o dia anterior' {
        $agora = [datetime]::new(2026, 9, 23, 2, 30, 0, [DateTimeKind]::Utc)
        Get-DataHojeBrasil -Agora $agora | Should -Be ([datetime]'2026-09-22')
    }

    It 'às 03:00 UTC (00:00 BRT) já é o dia seguinte' {
        $agora = [datetime]::new(2026, 9, 23, 3, 0, 0, [DateTimeKind]::Utc)
        Get-DataHojeBrasil -Agora $agora | Should -Be ([datetime]'2026-09-23')
    }

    It 'trata Kind Unspecified como UTC' {
        $agora = [datetime]::new(2026, 9, 23, 2, 30, 0, [DateTimeKind]::Unspecified)
        Get-DataHojeBrasil -Agora $agora | Should -Be ([datetime]'2026-09-22')
    }

    It 'converte Kind Local para UTC antes de aplicar o fuso' {
        $utc = [datetime]::new(2026, 9, 23, 2, 30, 0, [DateTimeKind]::Utc)
        Get-DataHojeBrasil -Agora $utc.ToLocalTime() | Should -Be ([datetime]'2026-09-22')
    }

    It 'retorna só a data, sem hora' {
        $resultado = Get-DataHojeBrasil -Agora ([datetime]::new(2026, 9, 22, 18, 45, 12, [DateTimeKind]::Utc))
        $resultado | Should -BeOfType [datetime]
        $resultado.TimeOfDay | Should -Be ([timespan]::Zero)
    }

    It 'sem -Agora usa o instante atual' {
        $esperado = Get-DataHojeBrasil -Agora ([datetime]::UtcNow)
        Get-DataHojeBrasil | Should -Be $esperado
    }
}

Describe 'Get-DiasRestantes' {
    It 'calcula <Esperado> dias de <Hoje> até <Vencimento>' -ForEach @(
        @{ Hoje = '2026-09-22'; Vencimento = '2026-10-22'; Esperado = 30 }
        @{ Hoje = '2026-09-22'; Vencimento = '2026-09-22'; Esperado = 0 }
        @{ Hoje = '2026-09-22'; Vencimento = '2026-09-21'; Esperado = -1 }
        @{ Hoje = '2026-12-31'; Vencimento = '2027-01-01'; Esperado = 1 }
        @{ Hoje = '2028-02-28'; Vencimento = '2028-03-01'; Esperado = 2 }   # ano bissexto
    ) {
        Get-DiasRestantes -DataVencimento $Vencimento -Hoje $Hoje | Should -Be $Esperado
    }

    It 'ignora a hora das datas recebidas' {
        $venc = [datetime]::new(2026, 9, 25, 23, 59, 0)
        $hoje = [datetime]::new(2026, 9, 22, 0, 1, 0)
        Get-DiasRestantes -DataVencimento $venc -Hoje $hoje | Should -Be 3
    }

    It 'retorna inteiro' {
        Get-DiasRestantes -DataVencimento '2026-10-01' -Hoje '2026-09-22' | Should -BeOfType [int]
    }

    It 'usa hoje em BRT por padrão' {
        $hoje = Get-DataHojeBrasil
        Get-DiasRestantes -DataVencimento $hoje.AddDays(10) | Should -Be 10
    }

    It 'rejeita data em formato inválido' {
        { Get-DiasRestantes -DataVencimento '15/03/2027' -Hoje '2026-09-22' } |
            Should -Throw -ExpectedMessage '*DataVencimento inválida*'
    }
}

Describe 'Get-MarcoDevido' {
    It 'fronteira: <Dias> dias → <Esperado>' -ForEach @(
        @{ Dias = 365; Esperado = $null }
        @{ Dias = 31; Esperado = $null }
        @{ Dias = 30; Esperado = '30' }
        @{ Dias = 16; Esperado = '30' }
        @{ Dias = 15; Esperado = '15' }
        @{ Dias = 8; Esperado = '15' }
        @{ Dias = 7; Esperado = '7' }
        @{ Dias = 1; Esperado = '7' }
        @{ Dias = 0; Esperado = '0' }
        @{ Dias = -1; Esperado = 'VENCIDO-0' }
        @{ Dias = -6; Esperado = 'VENCIDO-0' }
        @{ Dias = -7; Esperado = 'VENCIDO-1' }
        @{ Dias = -8; Esperado = 'VENCIDO-1' }
        @{ Dias = -13; Esperado = 'VENCIDO-1' }
        @{ Dias = -14; Esperado = 'VENCIDO-2' }
    ) {
        Get-MarcoDevido -DiasRestantes $Dias | Should -Be $Esperado
    }

    It 'exemplo da regra: 12 dias → marco 15' {
        Get-MarcoDevido -DiasRestantes 12 | Should -Be '15'
    }

    It 'exemplo da regra: 5 dias → marco 7' {
        Get-MarcoDevido -DiasRestantes 5 | Should -Be '7'
    }
}

Describe 'Test-AlertaPendente' {
    BeforeAll {
        $enviados = @(
            [pscustomobject]@{ ItemId = 'item-1'; DataVencimento = '2026-10-15'; Marco = '30' }
            [pscustomobject]@{ ItemId = 'item-1'; DataVencimento = '2026-10-15'; Marco = '15' }
            [pscustomobject]@{ ItemId = 'item-2'; DataVencimento = '2026-09-01'; Marco = 'VENCIDO-0' }
        )
    }

    It 'não pendente quando o marco já foi enviado para o mesmo item e data' {
        Test-AlertaPendente -ItemId 'item-1' -DataVencimento '2026-10-15' -Marco '15' -AlertasEnviados $enviados |
            Should -BeFalse
    }

    It 'pendente quando o marco ainda não foi enviado' {
        Test-AlertaPendente -ItemId 'item-1' -DataVencimento '2026-10-15' -Marco '7' -AlertasEnviados $enviados |
            Should -BeTrue
    }

    It 'renovação: data nova deixa o mesmo marco pendente de novo' {
        Test-AlertaPendente -ItemId 'item-1' -DataVencimento '2027-10-15' -Marco '30' -AlertasEnviados $enviados |
            Should -BeTrue
    }

    It 'não confunde itens diferentes' {
        Test-AlertaPendente -ItemId 'item-3' -DataVencimento '2026-10-15' -Marco '30' -AlertasEnviados $enviados |
            Should -BeTrue
    }

    It 'item vencido repete na semana seguinte (VENCIDO-1) mas não na mesma semana' {
        Test-AlertaPendente -ItemId 'item-2' -DataVencimento '2026-09-01' -Marco 'VENCIDO-0' -AlertasEnviados $enviados |
            Should -BeFalse
        Test-AlertaPendente -ItemId 'item-2' -DataVencimento '2026-09-01' -Marco 'VENCIDO-1' -AlertasEnviados $enviados |
            Should -BeTrue
    }

    It 'sem marco devido ($null) não há alerta pendente' {
        Test-AlertaPendente -ItemId 'item-1' -DataVencimento '2026-12-31' -Marco $null -AlertasEnviados $enviados |
            Should -BeFalse
    }

    It 'sem histórico de envios o marco está pendente' {
        Test-AlertaPendente -ItemId 'item-1' -DataVencimento '2026-10-15' -Marco '30' -AlertasEnviados @() |
            Should -BeTrue
        Test-AlertaPendente -ItemId 'item-1' -DataVencimento '2026-10-15' -Marco '30' |
            Should -BeTrue
    }

    It 'aceita DataVencimento como [datetime] e registros como hashtable' {
        $historico = @(@{ ItemId = 'item-9'; DataVencimento = [datetime]'2026-11-01'; Marco = '7' })
        Test-AlertaPendente -ItemId 'item-9' -DataVencimento ([datetime]'2026-11-01') -Marco '7' -AlertasEnviados $historico |
            Should -BeFalse
    }

    It 'item cadastrado tarde (10 dias) recebe só o marco 15, não o 30 retroativo' {
        $dias = Get-DiasRestantes -DataVencimento '2026-10-02' -Hoje '2026-09-22'
        $marco = Get-MarcoDevido -DiasRestantes $dias
        $marco | Should -Be '15'
        Test-AlertaPendente -ItemId 'novo' -DataVencimento '2026-10-02' -Marco $marco | Should -BeTrue

        # No dia seguinte o marco devido continua sendo 15, já enviado: nada de 30 retroativo.
        $enviado = @([pscustomobject]@{ ItemId = 'novo'; DataVencimento = '2026-10-02'; Marco = $marco })
        $marcoAmanha = Get-MarcoDevido -DiasRestantes (Get-DiasRestantes -DataVencimento '2026-10-02' -Hoje '2026-09-23')
        $marcoAmanha | Should -Be '15'
        Test-AlertaPendente -ItemId 'novo' -DataVencimento '2026-10-02' -Marco $marcoAmanha -AlertasEnviados $enviado |
            Should -BeFalse
    }
}

Describe 'ConvertTo-ItemNormalizado' {
    It 'normaliza um item válido' {
        $entrada = [pscustomobject]@{
            ClienteId      = 'cli-1'
            ItemId         = 'item-1'
            Tipo           = 'ssl'
            Alvo           = '  portal.cliente.com.br:443 '
            Descricao      = 'Portal'
            Titular        = ''
            DataVencimento = ''
            ContatosAlerta = ' a@cliente.com.br; b@cliente.com.br ;;'
            Ativo          = 'true'
        }

        $item = ConvertTo-ItemNormalizado -Item $entrada

        $item.Tipo | Should -BeExactly 'SSL'
        $item.Alvo | Should -BeExactly 'portal.cliente.com.br:443'
        $item.ContatosAlerta | Should -Be @('a@cliente.com.br', 'b@cliente.com.br')
        $item.ContatosAlerta.Count | Should -Be 2
        $item.DataVencimento | Should -BeNullOrEmpty
        $item.Ativo | Should -BeTrue
        $item.ClienteId | Should -Be 'cli-1'
        $item.ItemId | Should -Be 'item-1'
    }

    It 'aceita os tipos <Tipo>' -ForEach @(
        @{ Tipo = 'SSL' }, @{ Tipo = 'Dominio' }, @{ Tipo = 'CertA1' }, @{ Tipo = 'CertA3' }, @{ Tipo = 'Manual' }
    ) {
        $entrada = @{ Tipo = $Tipo; Alvo = 'x'; ContatosAlerta = 'a@b.com'; DataVencimento = '2027-03-15' }
        (ConvertTo-ItemNormalizado -Item $entrada).Tipo | Should -BeExactly $Tipo
    }

    It 'contato único vira array de um elemento' {
        $item = ConvertTo-ItemNormalizado -Item @{ Tipo = 'Dominio'; Alvo = 'cliente.com.br'; ContatosAlerta = 'a@b.com' }
        , $item.ContatosAlerta | Should -BeOfType [string[]]
        $item.ContatosAlerta.Count | Should -Be 1
    }

    It 'remove e-mails duplicados (sem diferenciar maiúsculas)' {
        $item = ConvertTo-ItemNormalizado -Item @{ Tipo = 'SSL'; Alvo = 'x'; ContatosAlerta = 'a@b.com;A@B.com;c@d.com' }
        $item.ContatosAlerta | Should -Be @('a@b.com', 'c@d.com')
    }

    It 'normaliza DataVencimento [datetime] para yyyy-MM-dd' {
        $item = ConvertTo-ItemNormalizado -Item @{ Tipo = 'CertA3'; Alvo = 'token'; ContatosAlerta = 'a@b.com'; DataVencimento = [datetime]'2027-03-15T10:00:00' }
        $item.DataVencimento | Should -BeExactly '2027-03-15'
    }

    It 'Ativo "<Entrada>" → <Esperado>' -ForEach @(
        @{ Entrada = 'false'; Esperado = $false }
        @{ Entrada = 'FALSE'; Esperado = $false }
        @{ Entrada = '0'; Esperado = $false }
        @{ Entrada = 'não'; Esperado = $false }
        @{ Entrada = '1'; Esperado = $true }
        @{ Entrada = 'sim'; Esperado = $true }
        @{ Entrada = $false; Esperado = $false }
        @{ Entrada = $null; Esperado = $true }
    ) {
        $item = ConvertTo-ItemNormalizado -Item @{ Tipo = 'SSL'; Alvo = 'x'; ContatosAlerta = 'a@b.com'; Ativo = $Entrada }
        $item.Ativo | Should -Be $Esperado
    }

    It 'aceita itens pelo pipeline (ex.: Import-Csv)' {
        $csv = @'
ClienteId,ItemId,Tipo,Alvo,ContatosAlerta,DataVencimento,Ativo
cli-1,i1,Dominio,cliente.com.br,a@b.com,,true
cli-1,i2,CertA3,token-a3,a@b.com;c@d.com,2027-03-15,true
'@ | ConvertFrom-Csv
        $itens = @($csv | ConvertTo-ItemNormalizado)
        $itens.Count | Should -Be 2
        $itens[1].ContatosAlerta.Count | Should -Be 2
    }

    Context 'validação' {
        It 'rejeita Tipo inválido' {
            { ConvertTo-ItemNormalizado -Item @{ Tipo = 'Outro'; Alvo = 'x'; ContatosAlerta = 'a@b.com' } } |
                Should -Throw -ExpectedMessage "*Tipo inválido: 'Outro'*"
        }

        It 'rejeita Tipo ausente' {
            { ConvertTo-ItemNormalizado -Item @{ Alvo = 'x'; ContatosAlerta = 'a@b.com' } } |
                Should -Throw -ExpectedMessage '*Tipo inválido*'
        }

        It 'rejeita Alvo vazio' {
            { ConvertTo-ItemNormalizado -Item @{ Tipo = 'SSL'; Alvo = '   '; ContatosAlerta = 'a@b.com' } } |
                Should -Throw -ExpectedMessage '*Alvo é obrigatório*'
        }

        It 'rejeita ContatosAlerta vazio' {
            { ConvertTo-ItemNormalizado -Item @{ Tipo = 'SSL'; Alvo = 'x'; ContatosAlerta = ' ; ' } } |
                Should -Throw -ExpectedMessage '*pelo menos um e-mail*'
        }

        It 'rejeita e-mail inválido' {
            { ConvertTo-ItemNormalizado -Item @{ Tipo = 'SSL'; Alvo = 'x'; ContatosAlerta = 'a@b.com;sem-arroba' } } |
                Should -Throw -ExpectedMessage "*E-mail inválido em ContatosAlerta: 'sem-arroba'*"
        }

        It 'exige DataVencimento para <Tipo>' -ForEach @(@{ Tipo = 'CertA3' }, @{ Tipo = 'Manual' }) {
            { ConvertTo-ItemNormalizado -Item @{ Tipo = $Tipo; Alvo = 'x'; ContatosAlerta = 'a@b.com' } } |
                Should -Throw -ExpectedMessage "*DataVencimento é obrigatória para o tipo $Tipo*"
        }

        It 'rejeita DataVencimento em formato inválido' {
            { ConvertTo-ItemNormalizado -Item @{ Tipo = 'Manual'; Alvo = 'x'; ContatosAlerta = 'a@b.com'; DataVencimento = '15/03/2027' } } |
                Should -Throw -ExpectedMessage '*DataVencimento inválida*'
        }

        It 'rejeita Ativo inválido' {
            { ConvertTo-ItemNormalizado -Item @{ Tipo = 'SSL'; Alvo = 'x'; ContatosAlerta = 'a@b.com'; Ativo = 'talvez' } } |
                Should -Throw -ExpectedMessage '*Ativo inválido*'
        }

        It 'lista todos os problemas e identifica o item' {
            $erro = $null
            try {
                ConvertTo-ItemNormalizado -Item @{ ItemId = 'i9'; Tipo = 'X'; Alvo = ''; ContatosAlerta = '' }
            }
            catch {
                $erro = $_.Exception.Message
            }
            $erro | Should -BeLike "Item 'i9' inválido:*"
            $erro | Should -BeLike '*Tipo inválido*'
            $erro | Should -BeLike '*Alvo é obrigatório*'
            $erro | Should -BeLike '*pelo menos um e-mail*'
        }
    }
}
