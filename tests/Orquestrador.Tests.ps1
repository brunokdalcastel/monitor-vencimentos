#Requires -Modules Pester

BeforeAll {
    Import-Module "$PSScriptRoot/../src/modules/Orquestrador/Orquestrador.psd1" -Force

    function Add-ItemFake {
        param(
            [string] $ItemId,
            [string] $ClienteId = 'cliente1',
            [string] $Tipo,
            [string] $Alvo,
            [object] $DataVencimento = $null,
            [string] $ContatosAlerta = 'contato@exemplo.com',
            [object] $Ativo = $true
        )

        $script:BancoItens[$ItemId] = [pscustomobject] @{
            PartitionKey   = $ClienteId
            RowKey         = $ItemId
            Tipo           = $Tipo
            Alvo           = $Alvo
            Descricao      = $null
            Titular        = $null
            DataVencimento = $DataVencimento
            ContatosAlerta = $ContatosAlerta
            Ativo          = $Ativo
        }
    }

    function Add-VerificacaoFake {
        param(
            [string] $ItemId,
            [string] $RowKey,
            [bool] $Sucesso
        )

        $script:BancoVerificacoes["$ItemId|$RowKey"] = [pscustomobject] @{
            PartitionKey = $ItemId
            RowKey       = $RowKey
            Sucesso      = $Sucesso
        }
    }

    function Add-AlertaEnviadoFake {
        param(
            [string] $ItemId,
            [string] $DataVencimento,
            [string] $Marco
        )

        $rowKey = "$($DataVencimento -replace '-', '')-$Marco"
        $script:BancoAlertasEnviados["$ItemId|$rowKey"] = [pscustomobject] @{
            PartitionKey   = $ItemId
            RowKey         = $rowKey
            ItemId         = $ItemId
            DataVencimento = $DataVencimento
            Marco          = $Marco
        }
    }
}

Describe 'Invoke-VerificacaoDiaria' {
    BeforeEach {
    $script:BancoItens = @{}
    $script:BancoVerificacoes = @{}
    $script:BancoAlertasEnviados = @{}
    $script:EmailsEnviados = New-Object System.Collections.Generic.List[object]
    $script:FalharEnvioPara = @()
    $env:ADMIN_EMAIL = $null

    Mock New-TabelaSeNaoExistir -ModuleName Orquestrador { }

    Mock Get-Entidades -ModuleName Orquestrador {
        switch ($Tabela) {
            'Itens' {
                $todos = @($script:BancoItens.Values)
                if ($Filtro -eq 'Ativo eq true') {
                    return , @($todos | Where-Object { $_.Ativo -eq $true })
                }
                return , $todos
            }
            'AlertasEnviados' {
                return , @($script:BancoAlertasEnviados.Values)
            }
            'Verificacoes' {
                $todos = @($script:BancoVerificacoes.Values)
                if ($Filtro -match "PartitionKey eq '([^']*)'") {
                    $pk = $Matches[1]
                    return , @($todos | Where-Object { $_.PartitionKey -eq $pk })
                }
                return , $todos
            }
            default {
                return , @()
            }
        }
    }

    Mock Set-Entidade -ModuleName Orquestrador {
        # Converte pra pscustomobject como um round-trip real por JSON faria
        # (o Storage de verdade grava e lê de volta via JSON) — um
        # hashtable/OrderedDictionary bruto não responde a .PSObject.Properties[...]
        # do jeito que uma entidade "lida do Storage" responde.
        $entidadeSalva = [pscustomobject] $Entidade
        $chave = "$($entidadeSalva.PartitionKey)|$($entidadeSalva.RowKey)"
        switch ($Tabela) {
            'Itens' { $script:BancoItens[$entidadeSalva.RowKey] = $entidadeSalva }
            'Verificacoes' { $script:BancoVerificacoes[$chave] = $entidadeSalva }
            'AlertasEnviados' { $script:BancoAlertasEnviados[$chave] = $entidadeSalva }
        }
    }

    Mock Remove-Entidade -ModuleName Orquestrador {
        $chave = "$PartitionKey|$RowKey"
        if ($Tabela -eq 'Verificacoes') { $script:BancoVerificacoes.Remove($chave) }
    }

    Mock New-EmailAlerta -ModuleName Orquestrador {
        return [pscustomobject] @{ Assunto = "Alerta para $Contato ($($Itens.Count) itens)"; Html = '<p>alerta</p>'; Texto = 'alerta' }
    }

    Mock New-EmailResumoAdmin -ModuleName Orquestrador {
        return [pscustomobject] @{ Assunto = 'Resumo diário'; Html = '<p>resumo</p>'; Texto = 'resumo' }
    }

    Mock Send-EmailAcs -ModuleName Orquestrador {
        if ($script:FalharEnvioPara -contains $Para) {
            throw "Falha simulada ao enviar para $Para"
        }
        $script:EmailsEnviados.Add([pscustomobject] @{ Para = $Para; Assunto = $Assunto })
        return [pscustomobject] @{ Status = 'Succeeded' }
    }

    # Ssl/Dominio: por padrão sem itens desses tipos nos testes; cada teste que
    # precisar mocka explicitamente.
    Mock ConvertTo-EnderecoSsl -ModuleName Orquestrador { return [pscustomobject] @{ Host = $Alvo; Porta = 443 } }
    Mock Get-CertificadoSsl -ModuleName Orquestrador { return [pscustomobject] @{ NotAfter = $null; Erro = 'não mockado neste teste' } }
    Mock Get-VencimentoDominio -ModuleName Orquestrador { return [pscustomobject] @{ DataExpiracao = $null; Status = 'Erro'; Erro = 'não mockado neste teste' } }
    }

    Context 'Cenário feliz' {
        It 'verifica um item Manual, envia o alerta e grava AlertasEnviados' {
            Add-ItemFake -ItemId 'item1' -Tipo 'Manual' -Alvo 'Certidão X' -DataVencimento '2026-10-01' -ContatosAlerta 'cliente@exemplo.com'

            $r = Invoke-VerificacaoDiaria -Hoje (Get-Date '2026-09-24')

            $r.TotalItensVerificados | Should -Be 1
            $r.Falhas.Count | Should -Be 0
            $r.AlertasEnviados.Count | Should -Be 1
            $r.AlertasEnviados[0].Contato | Should -Be 'cliente@exemplo.com'
            $r.AlertasEnviados[0].TotalItens | Should -Be 1

            $script:EmailsEnviados.Count | Should -Be 1
            $script:BancoAlertasEnviados.Count | Should -Be 1
            $script:BancoVerificacoes.Count | Should -Be 1
            ($script:BancoVerificacoes.Values | Select-Object -First 1).Sucesso | Should -Be $true
        }

        It 'verifica um item SSL com sucesso e atualiza a DataVencimento automaticamente' {
            Add-ItemFake -ItemId 'itemSsl' -Tipo 'SSL' -Alvo 'exemplo.com' -ContatosAlerta 'cliente@exemplo.com'
            Mock Get-CertificadoSsl -ModuleName Orquestrador {
                return [pscustomobject] @{ NotAfter = [datetime]::new(2026, 10, 1, 3, 0, 0, [DateTimeKind]::Utc); Erro = $null }
            }

            $r = Invoke-VerificacaoDiaria -Hoje (Get-Date '2026-09-24')

            $r.Falhas.Count | Should -Be 0
            $script:BancoItens['itemSsl'].DataVencimento | Should -Be '2026-10-01'
        }

        It 'verifica um item Dominio com sucesso' {
            Add-ItemFake -ItemId 'itemDom' -Tipo 'Dominio' -Alvo 'exemplo.com.br' -ContatosAlerta 'cliente@exemplo.com'
            Mock Get-VencimentoDominio -ModuleName Orquestrador {
                return [pscustomobject] @{ DataExpiracao = [datetime]::new(2026, 10, 15, 0, 0, 0, [DateTimeKind]::Utc); Status = 'Ok'; Erro = $null }
            }

            $r = Invoke-VerificacaoDiaria -Hoje (Get-Date '2026-09-24')

            $r.Falhas.Count | Should -Be 0
            $script:BancoItens['itemDom'].DataVencimento | Should -Be '2026-10-15'
        }
    }

    Context 'Item com falha' {
        It 'registra a falha, não envia alerta ao cliente e não atualiza a DataVencimento' {
            Add-ItemFake -ItemId 'itemFalha' -Tipo 'SSL' -Alvo 'fora-do-ar.com' -ContatosAlerta 'cliente@exemplo.com'
            Mock Get-CertificadoSsl -ModuleName Orquestrador {
                return [pscustomobject] @{ NotAfter = $null; Erro = 'Tempo esgotado ao conectar.' }
            }

            $r = Invoke-VerificacaoDiaria -Hoje (Get-Date '2026-09-24')

            $r.Falhas.Count | Should -Be 1
            $r.Falhas[0].Alvo | Should -Be 'fora-do-ar.com'
            $r.Falhas[0].Erro | Should -Be 'Tempo esgotado ao conectar.'
            $r.AlertasEnviados.Count | Should -Be 0
            $script:EmailsEnviados.Count | Should -Be 0
            ($script:BancoVerificacoes.Values | Select-Object -First 1).Sucesso | Should -Be $false
        }

        It 'avisa explicitamente o admin após 3 falhas de verificação seguidas' {
            Add-ItemFake -ItemId 'itemFalhaRepetida' -Tipo 'SSL' -Alvo 'sempre-fora.com' -ContatosAlerta 'cliente@exemplo.com'
            Add-VerificacaoFake -ItemId 'itemFalhaRepetida' -RowKey '20260922' -Sucesso $false
            Add-VerificacaoFake -ItemId 'itemFalhaRepetida' -RowKey '20260923' -Sucesso $false
            Mock Get-CertificadoSsl -ModuleName Orquestrador { return [pscustomobject] @{ NotAfter = $null; Erro = 'ainda fora do ar' } }
            $env:ADMIN_EMAIL = 'admin@exemplo.com'

            Invoke-VerificacaoDiaria -Hoje (Get-Date '2026-09-24') | Out-Null

            Should -Invoke New-EmailResumoAdmin -ModuleName Orquestrador -Times 1 -Exactly -ParameterFilter {
                $Falhas.Count -eq 1 -and $Falhas[0].Erro -match 'ATEN' -and $Falhas[0].Erro -match '3 verifica'
            }
        }

        It 'ignora itens CertA1 sem DataVencimento cadastrada (Fase 2 ainda não existe), sem contar como falha' {
            Add-ItemFake -ItemId 'itemA1' -Tipo 'CertA1' -Alvo 'thumbprint-x' -DataVencimento $null

            $r = Invoke-VerificacaoDiaria -Hoje (Get-Date '2026-09-24')

            $r.TotalItensVerificados | Should -Be 1
            $r.Falhas.Count | Should -Be 0
            $r.AlertasEnviados.Count | Should -Be 0
            $script:BancoVerificacoes.Count | Should -Be 0
        }

        It 'item com cadastro inválido vira falha e não interrompe os demais' {
            Add-ItemFake -ItemId 'itemInvalido' -Tipo 'TipoQueNaoExiste' -Alvo 'x' -ContatosAlerta 'cliente@exemplo.com'
            Add-ItemFake -ItemId 'itemValido' -Tipo 'Manual' -Alvo 'ok' -DataVencimento '2026-10-01' -ContatosAlerta 'cliente@exemplo.com'

            $r = Invoke-VerificacaoDiaria -Hoje (Get-Date '2026-09-24')

            $r.TotalItensVerificados | Should -Be 2
            $r.Falhas.Count | Should -Be 1
            $r.AlertasEnviados.Count | Should -Be 1
        }
    }

    Context 'Reexecução no mesmo dia (idempotência)' {
        It 'não duplica o alerta nem o registro de Verificacoes ao rodar duas vezes' {
            Add-ItemFake -ItemId 'itemIdempotente' -Tipo 'Manual' -Alvo 'x' -DataVencimento '2026-10-01' -ContatosAlerta 'cliente@exemplo.com'

            Invoke-VerificacaoDiaria -Hoje (Get-Date '2026-09-24') | Out-Null
            $r2 = Invoke-VerificacaoDiaria -Hoje (Get-Date '2026-09-24')

            $script:EmailsEnviados.Count | Should -Be 1
            $r2.AlertasEnviados.Count | Should -Be 0
            $script:BancoAlertasEnviados.Count | Should -Be 1
            $script:BancoVerificacoes.Count | Should -Be 1
        }
    }

    Context 'Renovação' {
        It 'a mudança de DataVencimento reabre o alerta para o mesmo marco' {
            Add-ItemFake -ItemId 'itemRenovado' -Tipo 'Manual' -Alvo 'x' -DataVencimento '2026-10-01' -ContatosAlerta 'cliente@exemplo.com'
            Invoke-VerificacaoDiaria -Hoje (Get-Date '2026-09-24') | Out-Null
            $script:EmailsEnviados.Count | Should -Be 1

            # Renova: nova data de vencimento, mesma distância em dias (mesmo marco '7').
            $script:BancoItens['itemRenovado'].DataVencimento = '2026-11-01'

            $r2 = Invoke-VerificacaoDiaria -Hoje (Get-Date '2026-10-25')

            $r2.AlertasEnviados.Count | Should -Be 1
            $script:EmailsEnviados.Count | Should -Be 2
            $script:BancoAlertasEnviados.Count | Should -Be 2
        }
    }

    Context 'Item vencido (semana 1 e semana 2)' {
        It 'gera alerta VENCIDO-0 na primeira semana e VENCIDO-1 na segunda' {
            Add-ItemFake -ItemId 'itemVencido' -Tipo 'Manual' -Alvo 'x' -DataVencimento '2026-09-20' -ContatosAlerta 'cliente@exemplo.com'

            $r1 = Invoke-VerificacaoDiaria -Hoje (Get-Date '2026-09-24')
            $r1.AlertasEnviados.Count | Should -Be 1
            $script:BancoAlertasEnviados.Keys | Should -Contain 'itemVencido|20260920-VENCIDO-0'

            $r2 = Invoke-VerificacaoDiaria -Hoje (Get-Date '2026-10-01')
            $r2.AlertasEnviados.Count | Should -Be 1
            $script:BancoAlertasEnviados.Keys | Should -Contain 'itemVencido|20260920-VENCIDO-1'

            $script:EmailsEnviados.Count | Should -Be 2
        }
    }

    Context 'Contato com vários itens' {
        It 'manda um único e-mail consolidado quando dois itens pendentes têm o mesmo contato' {
            Add-ItemFake -ItemId 'itemA' -Tipo 'Manual' -Alvo 'a' -DataVencimento '2026-10-01' -ContatosAlerta 'cliente@exemplo.com'
            Add-ItemFake -ItemId 'itemB' -Tipo 'Manual' -Alvo 'b' -DataVencimento '2026-10-05' -ContatosAlerta 'cliente@exemplo.com'

            $r = Invoke-VerificacaoDiaria -Hoje (Get-Date '2026-09-24')

            $script:EmailsEnviados.Count | Should -Be 1
            $r.AlertasEnviados.Count | Should -Be 1
            $r.AlertasEnviados[0].TotalItens | Should -Be 2
            Should -Invoke New-EmailAlerta -ModuleName Orquestrador -Times 1 -Exactly -ParameterFilter { $Itens.Count -eq 2 }
        }

        It 'manda um e-mail por contato quando os itens têm contatos diferentes' {
            Add-ItemFake -ItemId 'itemA' -Tipo 'Manual' -Alvo 'a' -DataVencimento '2026-10-01' -ContatosAlerta 'um@exemplo.com'
            Add-ItemFake -ItemId 'itemB' -Tipo 'Manual' -Alvo 'b' -DataVencimento '2026-10-05' -ContatosAlerta 'dois@exemplo.com'

            Invoke-VerificacaoDiaria -Hoje (Get-Date '2026-09-24') | Out-Null

            $script:EmailsEnviados.Count | Should -Be 2
        }
    }

    Context 'Falha parcial de envio' {
        It 'não grava AlertasEnviados para um item cujo contato falhou, mesmo com outro contato tendo recebido' {
            Add-ItemFake -ItemId 'itemMultiContato' -Tipo 'Manual' -Alvo 'x' -DataVencimento '2026-10-01' -ContatosAlerta 'ok@exemplo.com;falha@exemplo.com'
            $script:FalharEnvioPara = @('falha@exemplo.com')

            $r = Invoke-VerificacaoDiaria -Hoje (Get-Date '2026-09-24')

            $script:BancoAlertasEnviados.Count | Should -Be 0
            $r.Falhas | Where-Object { $_.Tipo -eq 'Email' -and $_.Alvo -eq 'falha@exemplo.com' } | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Limpeza de Verificacoes antigas' {
        It 'remove registros de Verificacoes com mais de 12 meses' {
            Add-VerificacaoFake -ItemId 'itemAntigo' -RowKey '20240101' -Sucesso $true
            Add-VerificacaoFake -ItemId 'itemAntigo' -RowKey '20260901' -Sucesso $true

            Invoke-VerificacaoDiaria -Hoje (Get-Date '2026-09-24') | Out-Null

            $script:BancoVerificacoes.ContainsKey('itemAntigo|20240101') | Should -Be $false
            $script:BancoVerificacoes.ContainsKey('itemAntigo|20260901') | Should -Be $true
        }
    }

    Context 'Resumo do admin' {
        It 'não tenta enviar resumo quando ADMIN_EMAIL não está configurado' {
            Add-ItemFake -ItemId 'item1' -Tipo 'Manual' -Alvo 'x' -DataVencimento '2026-10-01' -ContatosAlerta 'cliente@exemplo.com'

            Invoke-VerificacaoDiaria -Hoje (Get-Date '2026-09-24') | Out-Null

            Should -Invoke New-EmailResumoAdmin -ModuleName Orquestrador -Times 0 -Exactly
        }

        It 'envia o resumo ao ADMIN_EMAIL com os totais corretos' {
            Add-ItemFake -ItemId 'item1' -Tipo 'Manual' -Alvo 'x' -DataVencimento '2026-10-01' -ContatosAlerta 'cliente@exemplo.com'
            $env:ADMIN_EMAIL = 'admin@exemplo.com'

            Invoke-VerificacaoDiaria -Hoje (Get-Date '2026-09-24') | Out-Null

            Should -Invoke New-EmailResumoAdmin -ModuleName Orquestrador -Times 1 -Exactly -ParameterFilter {
                $TotalItensVerificados -eq 1 -and $AlertasEnviados.Count -eq 1
            }
            $script:EmailsEnviados | Where-Object { $_.Para -eq 'admin@exemplo.com' } | Should -Not -BeNullOrEmpty
        }
    }

    Context 'Itens sem marco devido' {
        It 'não gera alerta quando faltam mais de 30 dias' {
            Add-ItemFake -ItemId 'itemLonge' -Tipo 'Manual' -Alvo 'x' -DataVencimento '2027-06-01' -ContatosAlerta 'cliente@exemplo.com'

            $r = Invoke-VerificacaoDiaria -Hoje (Get-Date '2026-09-24')

            $r.AlertasEnviados.Count | Should -Be 0
            $script:EmailsEnviados.Count | Should -Be 0
            $script:BancoVerificacoes.Count | Should -Be 1
        }
    }
}
