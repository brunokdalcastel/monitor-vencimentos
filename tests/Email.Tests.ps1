#Requires -Modules Pester

BeforeAll {
    Import-Module "$PSScriptRoot/../src/modules/Email/Email.psd1" -Force
}

Describe 'ConvertTo-TextoHtmlSeguro' {
    It 'escapa tags HTML' {
        ConvertTo-TextoHtmlSeguro -Texto '<script>alert(1)</script>' | Should -Be '&lt;script&gt;alert(1)&lt;/script&gt;'
    }

    It 'escapa aspas simples e duplas' {
        (ConvertTo-TextoHtmlSeguro -Texto "O'Brien ""teste""") | Should -Match '&#39;|&quot;'
    }

    It 'não altera texto simples' {
        ConvertTo-TextoHtmlSeguro -Texto 'exemplo.com' | Should -Be 'exemplo.com'
    }

    It 'aceita string vazia' {
        ConvertTo-TextoHtmlSeguro -Texto '' | Should -Be ''
    }
}

Describe 'New-EmailAlerta' {
    It 'lança erro sem itens (parâmetro obrigatório permite lista vazia mas não nula)' {
        { New-EmailAlerta -Contato 'cliente@exemplo.com' -Itens @() } | Should -Not -Throw
    }

    It 'monta assunto com a contagem de itens (singular e plural)' {
        $itemUnico = @([pscustomobject] @{ Tipo = 'SSL'; Alvo = 'a.com'; DataVencimento = '2026-10-01'; Marco = '7' })
        $r1 = New-EmailAlerta -Contato 'c@exemplo.com' -Itens $itemUnico
        $r1.Assunto | Should -Be 'Monitor de Vencimentos: 1 alerta de vencimento'

        $doisItens = @(
            [pscustomobject] @{ Tipo = 'SSL'; Alvo = 'a.com'; DataVencimento = '2026-10-01'; Marco = '7' }
            [pscustomobject] @{ Tipo = 'SSL'; Alvo = 'b.com'; DataVencimento = '2026-10-02'; Marco = '7' }
        )
        $r2 = New-EmailAlerta -Contato 'c@exemplo.com' -Itens $doisItens
        $r2.Assunto | Should -Be 'Monitor de Vencimentos: 2 alertas de vencimento'
    }

    It 'agrupa e ordena por urgência: vencidos -> 0 -> 7 -> 15 -> 30' {
        $itens = @(
            [pscustomobject] @{ Tipo = 'SSL'; Alvo = 'trinta.com'; DataVencimento = '2026-10-24'; Marco = '30' }
            [pscustomobject] @{ Tipo = 'SSL'; Alvo = 'quinze.com'; DataVencimento = '2026-10-09'; Marco = '15' }
            [pscustomobject] @{ Tipo = 'SSL'; Alvo = 'sete.com'; DataVencimento = '2026-10-01'; Marco = '7' }
            [pscustomobject] @{ Tipo = 'Dominio'; Alvo = 'hoje.com'; DataVencimento = '2026-09-24'; Marco = '0' }
            [pscustomobject] @{ Tipo = 'CertA3'; Alvo = 'vencido2.com'; DataVencimento = '2026-09-10'; Marco = 'VENCIDO-2' }
            [pscustomobject] @{ Tipo = 'CertA3'; Alvo = 'vencido1.com'; DataVencimento = '2026-09-17'; Marco = 'VENCIDO-1' }
        )

        $r = New-EmailAlerta -Contato 'c@exemplo.com' -Itens $itens

        # Vencidos primeiro (ordenados por data, o mais antigo/vencido há mais tempo primeiro), depois 0, 7, 15, 30
        $ordemEsperada = @('vencido2.com', 'vencido1.com', 'hoje.com', 'sete.com', 'quinze.com', 'trinta.com')
        $posicoes = $ordemEsperada | ForEach-Object { $r.Texto.IndexOf($_) }
        for ($i = 1; $i -lt $posicoes.Count; $i++) {
            $posicoes[$i] | Should -BeGreaterThan $posicoes[$i - 1]
        }

        $r.Html | Should -Match 'Vencido\(s\)'
        $r.Html | Should -Match 'Vence hoje'
        $r.Html | Should -Match 'Vence em at.{1,10}7 dias'
        $r.Html | Should -Match 'Vence em at.{1,10}15 dias'
        $r.Html | Should -Match 'Vence em at.{1,10}30 dias'
    }

    It 'formata a data de vencimento como dd/MM/yyyy' {
        $itens = @([pscustomobject] @{ Tipo = 'SSL'; Alvo = 'a.com'; DataVencimento = '2026-01-05'; Marco = '7' })
        $r = New-EmailAlerta -Contato 'c@exemplo.com' -Itens $itens
        $r.Html | Should -Match '05/01/2026'
        $r.Texto | Should -Match '05/01/2026'
    }

    It 'aceita DataVencimento como [datetime]' {
        $itens = @([pscustomobject] @{ Tipo = 'SSL'; Alvo = 'a.com'; DataVencimento = (Get-Date '2026-03-15'); Marco = '7' })
        $r = New-EmailAlerta -Contato 'c@exemplo.com' -Itens $itens
        $r.Html | Should -Match '15/03/2026'
    }

    It 'escapa HTML no Alvo (campo de cadastro)' {
        $itens = @([pscustomobject] @{ Tipo = 'Dominio'; Alvo = '<img src=x onerror=alert(1)>'; DataVencimento = '2026-10-01'; Marco = '7' })
        $r = New-EmailAlerta -Contato 'c@exemplo.com' -Itens $itens
        $r.Html | Should -Not -Match '<img'
        $r.Html | Should -Match '&lt;img'
    }

    It 'escapa HTML no Contato (campo de cadastro) exibido no rodapé' {
        $itens = @([pscustomobject] @{ Tipo = 'SSL'; Alvo = 'a.com'; DataVencimento = '2026-10-01'; Marco = '7' })
        $r = New-EmailAlerta -Contato '<b>c@exemplo.com</b>' -Itens $itens
        $r.Html | Should -Not -Match '<b>c@exemplo.com'
        $r.Html | Should -Match '&lt;b&gt;'
    }
}

Describe 'New-EmailResumoAdmin' {
    It 'mostra os totais corretos' {
        $r = New-EmailResumoAdmin -Data (Get-Date '2026-09-24') -TotalItensVerificados 10 -AlertasEnviados @(
            [pscustomobject] @{ Contato = 'a@exemplo.com'; TotalItens = 2 }
        ) -Falhas @(
            [pscustomobject] @{ Tipo = 'SSL'; Alvo = 'falhou.com'; Erro = 'timeout' }
        )

        $r.Html | Should -Match 'Itens verificados:.*10'
        $r.Html | Should -Match 'Alertas enviados:.*1'
        $r.Html | Should -Match 'Falhas de verifica.{1,3}o:.*1'
        $r.Assunto | Should -Match '24/09/2026'
    }

    It 'aceita listas vazias' {
        { New-EmailResumoAdmin -Data (Get-Date) -TotalItensVerificados 0 } | Should -Not -Throw
    }

    It 'escapa HTML no Alvo e no Erro das falhas' {
        $r = New-EmailResumoAdmin -Data (Get-Date) -TotalItensVerificados 1 -Falhas @(
            [pscustomobject] @{ Tipo = 'Dominio'; Alvo = '<script>x</script>'; Erro = '<b>erro</b>' }
        )

        $r.Html | Should -Not -Match '<script>'
        $r.Html | Should -Not -Match '<b>erro'
        $r.Html | Should -Match '&lt;script&gt;'
    }
}

Describe 'Send-EmailAcs' {
    Context 'Modo Arquivo' {
        BeforeEach {
            $script:diretorioTeste = Join-Path ([System.IO.Path]::GetTempPath()) ("email-teste-" + [guid]::NewGuid().ToString('N'))
            $env:EMAIL_MODO = 'Arquivo'
            $env:EMAIL_SAIDA_DIR = $script:diretorioTeste
        }

        AfterEach {
            $env:EMAIL_MODO = $null
            $env:EMAIL_SAIDA_DIR = $null
            if (Test-Path -LiteralPath $script:diretorioTeste) {
                Remove-Item -LiteralPath $script:diretorioTeste -Recurse -Force
            }
        }

        It 'grava o HTML em EMAIL_SAIDA_DIR em vez de enviar' {
            $resultado = Send-EmailAcs -Para 'cliente@exemplo.com' -Assunto 'Assunto' -Html '<p>Ola</p>' -Texto 'Ola'

            $resultado.Status | Should -Be 'Arquivo'
            Test-Path -LiteralPath $resultado.Caminho | Should -Be $true
            Get-Content -LiteralPath $resultado.Caminho -Raw | Should -Match '<p>Ola</p>'
        }

        It 'usa ./saida-emails como padrão quando EMAIL_SAIDA_DIR não está definido' {
            $env:EMAIL_SAIDA_DIR = $null
            New-Item -ItemType Directory -Path $script:diretorioTeste -Force | Out-Null
            Push-Location $script:diretorioTeste
            try {
                $resultado = Send-EmailAcs -Para 'cliente@exemplo.com' -Assunto 'Assunto' -Html '<p>Ola</p>' -Texto 'Ola'
                $resultado.Caminho | Should -Match ([regex]::Escape('saida-emails'))
            }
            finally {
                Pop-Location
            }
        }
    }

    Context 'Modo Envio (Invoke-WebRequest/Invoke-RestMethod mockados)' {
        BeforeEach {
            $env:EMAIL_MODO = $null
            $env:ACS_ENDPOINT = 'https://minhaconta.communication.azure.com'
            $env:ACS_REMETENTE = 'DoNotReply@minhaconta.azurecomm.net'
        }

        AfterEach {
            $env:EMAIL_MODO = $null
            $env:ACS_ENDPOINT = $null
            $env:ACS_REMETENTE = $null
        }

        It 'lança erro sem ACS_ENDPOINT/ACS_REMETENTE' {
            $env:ACS_ENDPOINT = $null
            { Send-EmailAcs -Para 'c@exemplo.com' -Assunto 'A' -Html '<p>x</p>' -Texto 'x' } | Should -Throw
        }

        It 'envia e acompanha o Operation-Location até Succeeded' {
            Mock Get-TokenAcesso -ModuleName Email { return 'token-123' }
            Mock Invoke-WebRequest -ModuleName Email {
                $Uri | Should -Match 'emails:send'
                $Headers['Authorization'] | Should -Be 'Bearer token-123'
                return [pscustomobject] @{
                    StatusCode = 202
                    Headers    = @{ 'Operation-Location' = 'https://minhaconta.communication.azure.com/emails/operations/op-1' }
                }
            }
            $script:chamada = 0
            Mock Invoke-RestMethod -ModuleName Email {
                $script:chamada++
                if ($script:chamada -lt 2) {
                    return [pscustomobject] @{ status = 'Running' }
                }
                return [pscustomobject] @{ status = 'Succeeded' }
            }

            $resultado = Send-EmailAcs -Para 'c@exemplo.com' -Assunto 'A' -Html '<p>x</p>' -Texto 'x' -IntervaloPollingMs 1

            $resultado.Status | Should -Be 'Succeeded'
            Should -Invoke Invoke-RestMethod -ModuleName Email -Times 2 -Exactly
        }

        It 'lança erro quando o status final é Failed' {
            Mock Get-TokenAcesso -ModuleName Email { return 'token-123' }
            Mock Invoke-WebRequest -ModuleName Email {
                return [pscustomobject] @{
                    StatusCode = 202
                    Headers    = @{ 'Operation-Location' = 'https://minhaconta.communication.azure.com/emails/operations/op-1' }
                }
            }
            Mock Invoke-RestMethod -ModuleName Email {
                return [pscustomobject] @{ status = 'Failed'; error = @{ message = 'Endereço de remetente inválido' } }
            }

            { Send-EmailAcs -Para 'c@exemplo.com' -Assunto 'A' -Html '<p>x</p>' -Texto 'x' -IntervaloPollingMs 1 } | Should -Throw '*Endereço de remetente inválido*'
        }

        It 'lança erro quando estoura o timeout aguardando o status' {
            Mock Get-TokenAcesso -ModuleName Email { return 'token-123' }
            Mock Invoke-WebRequest -ModuleName Email {
                return [pscustomobject] @{
                    StatusCode = 202
                    Headers    = @{ 'Operation-Location' = 'https://minhaconta.communication.azure.com/emails/operations/op-1' }
                }
            }
            Mock Invoke-RestMethod -ModuleName Email {
                return [pscustomobject] @{ status = 'Running' }
            }

            { Send-EmailAcs -Para 'c@exemplo.com' -Assunto 'A' -Html '<p>x</p>' -Texto 'x' -TimeoutSegundos 0 -IntervaloPollingMs 1 } | Should -Throw '*Tempo esgotado*'
        }

        It 'lança erro quando a resposta não tem Operation-Location' {
            Mock Get-TokenAcesso -ModuleName Email { return 'token-123' }
            Mock Invoke-WebRequest -ModuleName Email {
                return [pscustomobject] @{ StatusCode = 202; Headers = @{} }
            }

            { Send-EmailAcs -Para 'c@exemplo.com' -Assunto 'A' -Html '<p>x</p>' -Texto 'x' } | Should -Throw '*Operation-Location*'
        }
    }
}
