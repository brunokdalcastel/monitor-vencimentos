#Requires -Modules Pester

BeforeAll {
    Import-Module "$PSScriptRoot/../src/modules/Identidade/Identidade.psd1" -Force
}

Describe 'Get-TokenAcesso' {
    BeforeEach {
        $script:enderecoOriginal = $env:IDENTITY_ENDPOINT
        $script:cabecalhoOriginal = $env:IDENTITY_HEADER
        $env:IDENTITY_ENDPOINT = 'http://169.254.129.2:8081/msi/token'
        $env:IDENTITY_HEADER = 'header-secreto'
    }

    AfterEach {
        $env:IDENTITY_ENDPOINT = $script:enderecoOriginal
        $env:IDENTITY_HEADER = $script:cabecalhoOriginal
    }

    It 'chama o endpoint de identidade com o recurso informado e devolve o token' {
        Mock Invoke-RestMethod -ModuleName Identidade {
            # .AbsoluteUri (e não o ToString() padrão) porque o Windows PowerShell 5.1
            # (.NET Framework) decodifica ':' e '/' de volta no ToString() de [uri],
            # diferente do 7.x — só .AbsoluteUri fica estável nas duas runtimes.
            $Uri.AbsoluteUri | Should -Match ([regex]::Escape('resource=https%3A%2F%2Fstorage.azure.com'))
            $Headers['X-IDENTITY-HEADER'] | Should -Be 'header-secreto'
            return [pscustomobject] @{ access_token = 'token-abc'; expires_on = [string] ([DateTimeOffset]::UtcNow.AddHours(1).ToUnixTimeSeconds()) }
        }

        $token = Get-TokenAcesso -Recurso 'https://storage.azure.com'
        $token | Should -Be 'token-abc'
    }

    It 'usa o cache em chamadas subsequentes para o mesmo recurso' {
        Mock Invoke-RestMethod -ModuleName Identidade {
            return [pscustomobject] @{ access_token = 'token-cache'; expires_on = [string] ([DateTimeOffset]::UtcNow.AddHours(1).ToUnixTimeSeconds()) }
        }

        Get-TokenAcesso -Recurso 'https://storage.azure.com/teste-cache' | Out-Null
        Get-TokenAcesso -Recurso 'https://storage.azure.com/teste-cache' | Out-Null

        Should -Invoke Invoke-RestMethod -ModuleName Identidade -Times 1 -Exactly
    }

    It 'não confunde o cache de recursos diferentes' {
        Mock Invoke-RestMethod -ModuleName Identidade {
            return [pscustomobject] @{ access_token = "token-$Uri"; expires_on = [string] ([DateTimeOffset]::UtcNow.AddHours(1).ToUnixTimeSeconds()) }
        }

        Get-TokenAcesso -Recurso 'https://storage.azure.com/teste-recurso-a' | Out-Null
        Get-TokenAcesso -Recurso 'https://communication.azure.com/teste-recurso-b' | Out-Null

        Should -Invoke Invoke-RestMethod -ModuleName Identidade -Times 2 -Exactly
    }

    It 'busca um novo token quando o cache expirou' {
        $script:chamada = 0
        Mock Invoke-RestMethod -ModuleName Identidade {
            $script:chamada++
            $expiraEm = if ($script:chamada -eq 1) { [DateTimeOffset]::UtcNow.AddSeconds(-100) } else { [DateTimeOffset]::UtcNow.AddHours(1) }
            return [pscustomobject] @{ access_token = "token-$($script:chamada)"; expires_on = [string] ($expiraEm.ToUnixTimeSeconds()) }
        }

        $t1 = Get-TokenAcesso -Recurso 'https://storage.azure.com/teste-expira' -MargemExpiracaoSegundos 0
        $t2 = Get-TokenAcesso -Recurso 'https://storage.azure.com/teste-expira' -MargemExpiracaoSegundos 0

        $t1 | Should -Be 'token-1'
        $t2 | Should -Be 'token-2'
        Should -Invoke Invoke-RestMethod -ModuleName Identidade -Times 2 -Exactly
    }

    It 'lança erro quando IDENTITY_ENDPOINT não está configurado' {
        $env:IDENTITY_ENDPOINT = $null
        { Get-TokenAcesso -Recurso 'https://storage.azure.com/teste-sem-endpoint' } | Should -Throw
    }

    It 'lança erro quando IDENTITY_HEADER não está configurado' {
        $env:IDENTITY_HEADER = $null
        { Get-TokenAcesso -Recurso 'https://storage.azure.com/teste-sem-header' } | Should -Throw
    }
}
