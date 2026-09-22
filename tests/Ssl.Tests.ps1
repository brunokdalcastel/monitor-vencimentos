#Requires -Modules Pester

BeforeAll {
    Import-Module "$PSScriptRoot/../src/modules/Ssl/Ssl.psd1" -Force
}

Describe 'ConvertTo-EnderecoSsl' {
    Context 'Formato host simples' {
        It 'usa a porta padrão 443 quando só o host é informado' {
            $r = ConvertTo-EnderecoSsl -Alvo 'exemplo.com'
            $r.Host | Should -Be 'exemplo.com'
            $r.Porta | Should -Be 443
        }

        It 'aceita espaços nas pontas' {
            $r = ConvertTo-EnderecoSsl -Alvo '  exemplo.com  '
            $r.Host | Should -Be 'exemplo.com'
        }

        It 'respeita -PortaPadrao quando informado' {
            $r = ConvertTo-EnderecoSsl -Alvo 'exemplo.com' -PortaPadrao 8443
            $r.Porta | Should -Be 8443
        }
    }

    Context 'Formato host:porta' {
        It 'lê a porta explícita' {
            $r = ConvertTo-EnderecoSsl -Alvo 'exemplo.com:8443'
            $r.Host | Should -Be 'exemplo.com'
            $r.Porta | Should -Be 8443
        }

        It 'rejeita porta não numérica' {
            { ConvertTo-EnderecoSsl -Alvo 'exemplo.com:abc' } | Should -Throw
        }

        It 'rejeita porta 0' {
            { ConvertTo-EnderecoSsl -Alvo 'exemplo.com:0' } | Should -Throw
        }

        It 'rejeita porta acima de 65535' {
            { ConvertTo-EnderecoSsl -Alvo 'exemplo.com:70000' } | Should -Throw
        }

        It 'rejeita mais de dois segmentos separados por dois-pontos' {
            { ConvertTo-EnderecoSsl -Alvo 'a:b:c' } | Should -Throw
        }
    }

    Context 'Formato URL https://' {
        It 'extrai o host, porta padrão 443, sem porta explícita na URL' {
            $r = ConvertTo-EnderecoSsl -Alvo 'https://exemplo.com'
            $r.Host | Should -Be 'exemplo.com'
            $r.Porta | Should -Be 443
        }

        It 'extrai o host ignorando o caminho' {
            $r = ConvertTo-EnderecoSsl -Alvo 'https://exemplo.com/algum/caminho'
            $r.Host | Should -Be 'exemplo.com'
            $r.Porta | Should -Be 443
        }

        It 'extrai a porta explícita da URL' {
            $r = ConvertTo-EnderecoSsl -Alvo 'https://exemplo.com:8443/algum/caminho'
            $r.Host | Should -Be 'exemplo.com'
            $r.Porta | Should -Be 8443
        }
    }

    Context 'Entradas inválidas' {
        It 'rejeita Alvo vazio' {
            { ConvertTo-EnderecoSsl -Alvo '' } | Should -Throw
        }

        It 'rejeita Alvo só com espaços' {
            { ConvertTo-EnderecoSsl -Alvo '   ' } | Should -Throw
        }

        It 'rejeita URL https:// sem host' {
            { ConvertTo-EnderecoSsl -Alvo 'https:///caminho' } | Should -Throw
        }
    }
}

Describe 'Get-CertificadoSsl' -Tag 'Integration' {
    It 'lê um certificado vencido (expired.badssl.com) e reporta cadeia inválida' {
        $r = Get-CertificadoSsl -Host 'expired.badssl.com' -Porta 443
        $r.Erro | Should -BeNullOrEmpty
        $r.Thumbprint | Should -Not -BeNullOrEmpty
        $r.NotAfter | Should -BeOfType [datetime]
        $r.NotAfter | Should -BeLessThan (Get-Date).ToUniversalTime()
        $r.CadeiaValida | Should -Be $false
        ($r.ErrosCadeia -join ';') | Should -Match 'NotTimeValid'
    }

    It 'lê um certificado autoassinado (self-signed.badssl.com) e reporta cadeia inválida' {
        $r = Get-CertificadoSsl -Host 'self-signed.badssl.com' -Porta 443
        $r.Erro | Should -BeNullOrEmpty
        $r.Thumbprint | Should -Not -BeNullOrEmpty
        $r.CadeiaValida | Should -Be $false
        ($r.ErrosCadeia -join ';') | Should -Match 'UntrustedRoot|PartialChain'
    }

    It 'lê um certificado válido (google.com) e reporta cadeia válida' {
        $r = Get-CertificadoSsl -Host 'google.com' -Porta 443
        $r.Erro | Should -BeNullOrEmpty
        $r.Thumbprint | Should -Not -BeNullOrEmpty
        $r.NotAfter | Should -BeGreaterThan (Get-Date).ToUniversalTime()
        $r.CadeiaValida | Should -Be $true
        $r.ErrosCadeia | Should -BeNullOrEmpty
    }

    It 'reporta Erro (não lança exceção) quando o host não existe' {
        $r = Get-CertificadoSsl -Host 'host-que-nao-existe.invalid' -Porta 443 -TimeoutMs 5000
        $r.Erro | Should -Not -BeNullOrEmpty
        $r.Thumbprint | Should -BeNullOrEmpty
    }
}
