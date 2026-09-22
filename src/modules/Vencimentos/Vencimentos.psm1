#Requires -Version 5.1
# Módulo Vencimentos — regras puras de vencimento e marcos de alerta (T02).
# Sem acesso a rede ou Azure: tudo aqui é determinístico e testável.
# Compatível com PowerShell 7.4 (Functions) e Windows PowerShell 5.1.

Set-StrictMode -Version Latest

$script:TiposValidos = @('SSL', 'Dominio', 'CertA1', 'CertA3', 'Manual')
# Tipos cuja DataVencimento não é descoberta automaticamente e precisa vir do cadastro.
$script:TiposComDataCadastrada = @('CertA3', 'Manual')
$script:RegexEmail = '^[^@\s;,<>"]+@[^@\s;,<>"]+\.[^@\s;,<>"]+$'
$script:FusoBrasil = $null

function Get-FusoBrasil {
    # IANA no Linux/.NET 6+; ID do Windows no .NET Framework (Windows PowerShell 5.1).
    if ($null -eq $script:FusoBrasil) {
        foreach ($id in @('America/Sao_Paulo', 'E. South America Standard Time')) {
            try {
                $script:FusoBrasil = [System.TimeZoneInfo]::FindSystemTimeZoneById($id)
                break
            }
            catch {
                continue
            }
        }
        if ($null -eq $script:FusoBrasil) {
            throw 'Fuso horário America/Sao_Paulo não encontrado neste sistema.'
        }
    }
    return $script:FusoBrasil
}

function ConvertTo-DataSemHora {
    # Aceita [datetime] ou texto 'yyyy-MM-dd' e devolve só a data (Kind Unspecified).
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Valor,

        [Parameter(Mandatory)]
        [string] $NomeCampo
    )

    if ($Valor -is [datetime]) {
        return [datetime]::SpecifyKind($Valor.Date, [System.DateTimeKind]::Unspecified)
    }

    $texto = [string] $Valor
    $data = [datetime]::MinValue
    $ok = [datetime]::TryParseExact(
        $texto.Trim(),
        'yyyy-MM-dd',
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::None,
        [ref] $data
    )
    if (-not $ok) {
        throw "$NomeCampo inválida: '$texto'. Use o formato yyyy-MM-dd."
    }
    return $data
}

function Get-DataHojeBrasil {
    <#
    .SYNOPSIS
        Data de hoje (sem hora) no fuso America/Sao_Paulo.
    .PARAMETER Agora
        Instante de referência. Padrão: agora (UTC). Valores com Kind Unspecified
        são tratados como UTC; Kind Local é convertido para UTC antes.
    #>
    [CmdletBinding()]
    [OutputType([datetime])]
    param(
        [datetime] $Agora = [datetime]::UtcNow
    )

    switch ($Agora.Kind) {
        'Local' { $utc = $Agora.ToUniversalTime() }
        'Utc' { $utc = $Agora }
        default { $utc = [datetime]::SpecifyKind($Agora, [System.DateTimeKind]::Utc) }
    }

    $local = [System.TimeZoneInfo]::ConvertTimeFromUtc($utc, (Get-FusoBrasil))
    return [datetime]::SpecifyKind($local.Date, [System.DateTimeKind]::Unspecified)
}

function Get-DiasRestantes {
    <#
    .SYNOPSIS
        Dias entre hoje e a data de vencimento (negativo = vencido).
    .PARAMETER DataVencimento
        [datetime] ou texto 'yyyy-MM-dd'. Só a data é considerada.
    .PARAMETER Hoje
        Data de referência. Padrão: Get-DataHojeBrasil.
    #>
    # Nome definido no PLANO.md; "Restantes" é plural em português, não um erro de nomenclatura.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '', Justification = 'Nome definido no PLANO.md (T02).')]
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [object] $DataVencimento,

        [object] $Hoje = (Get-DataHojeBrasil)
    )

    $vencimento = ConvertTo-DataSemHora -Valor $DataVencimento -NomeCampo 'DataVencimento'
    $referencia = ConvertTo-DataSemHora -Valor $Hoje -NomeCampo 'Hoje'
    return ($vencimento - $referencia).Days
}

function Get-MarcoDevido {
    <#
    .SYNOPSIS
        Marco de alerta mais urgente já alcançado: '30', '15', '7', '0', 'VENCIDO-n' ou $null.
    .DESCRIPTION
        Mais de 30 dias: $null (nada a alertar). Vencido (dias < 0): 'VENCIDO-n' com
        n = floor(|dias| / 7), para que o alerta se repita a cada 7 dias (ADR 0009).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [int] $DiasRestantes
    )

    if ($DiasRestantes -lt 0) {
        $semana = [int] [math]::Floor([math]::Abs($DiasRestantes) / 7)
        return "VENCIDO-$semana"
    }
    if ($DiasRestantes -eq 0) { return '0' }
    if ($DiasRestantes -le 7) { return '7' }
    if ($DiasRestantes -le 15) { return '15' }
    if ($DiasRestantes -le 30) { return '30' }
    return $null
}

function Test-AlertaPendente {
    <#
    .SYNOPSIS
        $true se o marco ainda não foi enviado para ItemId + DataVencimento (ADR 0008).
    .PARAMETER AlertasEnviados
        Registros já enviados, cada um com as propriedades ItemId, DataVencimento e Marco.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string] $ItemId,

        [Parameter(Mandatory)]
        [object] $DataVencimento,

        [Parameter(Mandatory)]
        [AllowNull()]
        [AllowEmptyString()]
        [string] $Marco,

        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $AlertasEnviados = @()
    )

    # Sem marco devido (mais de 30 dias) não há o que enviar.
    if ([string]::IsNullOrWhiteSpace($Marco)) {
        return $false
    }

    $dataIso = (ConvertTo-DataSemHora -Valor $DataVencimento -NomeCampo 'DataVencimento').ToString('yyyy-MM-dd')

    foreach ($alerta in @($AlertasEnviados)) {
        if ($null -eq $alerta) { continue }
        if ([string] (Get-ValorCampo $alerta 'ItemId') -ne $ItemId) { continue }
        if ([string] (Get-ValorCampo $alerta 'Marco') -ne $Marco) { continue }
        $dataAlerta = (ConvertTo-DataSemHora -Valor (Get-ValorCampo $alerta 'DataVencimento') -NomeCampo 'DataVencimento do alerta').ToString('yyyy-MM-dd')
        if ($dataAlerta -eq $dataIso) {
            return $false
        }
    }
    return $true
}

function Get-ValorCampo {
    param(
        [Parameter(Mandatory)] [object] $Objeto,
        [Parameter(Mandatory)] [string] $Nome
    )

    if ($Objeto -is [System.Collections.IDictionary]) {
        if ($Objeto.Contains($Nome)) { return $Objeto[$Nome] }
        return $null
    }
    $propriedade = $Objeto.PSObject.Properties[$Nome]
    if ($null -eq $propriedade) { return $null }
    return $propriedade.Value
}

function ConvertTo-ItemNormalizado {
    <#
    .SYNOPSIS
        Valida e normaliza um item do inventário (linha de CSV ou entidade da tabela Itens).
    .DESCRIPTION
        - Tipo: um de SSL, Dominio, CertA1, CertA3, Manual (sem diferenciar maiúsculas).
        - Alvo: obrigatório, sem espaços nas pontas.
        - ContatosAlerta: e-mails separados por ';' → array, sem vazios nem duplicados.
        - DataVencimento: opcional, 'yyyy-MM-dd'; obrigatória para CertA3 e Manual.
        - Ativo: padrão $true; aceita true/false/1/0/sim/não.
        Lança exceção listando todos os problemas encontrados.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object] $Item
    )

    process {
        $erros = New-Object System.Collections.Generic.List[string]

        # Tipo
        $tipoEntrada = ([string] (Get-ValorCampo $Item 'Tipo')).Trim()
        $tipo = $script:TiposValidos | Where-Object { $_ -eq $tipoEntrada } | Select-Object -First 1
        if ($null -eq $tipo) {
            $erros.Add("Tipo inválido: '$tipoEntrada'. Valores aceitos: $($script:TiposValidos -join ', ').")
        }

        # Alvo
        $alvo = ([string] (Get-ValorCampo $Item 'Alvo')).Trim()
        if ($alvo -eq '') {
            $erros.Add('Alvo é obrigatório.')
        }

        # ContatosAlerta
        $contatosEntrada = Get-ValorCampo $Item 'ContatosAlerta'
        $contatos = New-Object System.Collections.Generic.List[string]
        foreach ($parte in @($contatosEntrada)) {
            foreach ($email in ([string] $parte).Split(';')) {
                $email = $email.Trim()
                if ($email -eq '') { continue }
                if ($email -notmatch $script:RegexEmail) {
                    $erros.Add("E-mail inválido em ContatosAlerta: '$email'.")
                    continue
                }
                if (-not ($contatos | Where-Object { $_ -eq $email })) {
                    $contatos.Add($email)
                }
            }
        }
        if ($contatos.Count -eq 0 -and -not ($erros | Where-Object { $_ -like 'E-mail inválido*' })) {
            $erros.Add('ContatosAlerta precisa de pelo menos um e-mail.')
        }

        # DataVencimento
        $dataVencimento = $null
        $dataEntrada = Get-ValorCampo $Item 'DataVencimento'
        if ($null -ne $dataEntrada -and ([string] $dataEntrada).Trim() -ne '') {
            try {
                $dataVencimento = (ConvertTo-DataSemHora -Valor $dataEntrada -NomeCampo 'DataVencimento').ToString('yyyy-MM-dd')
            }
            catch {
                $erros.Add($_.Exception.Message)
            }
        }
        elseif ($null -ne $tipo -and $script:TiposComDataCadastrada -contains $tipo) {
            $erros.Add("DataVencimento é obrigatória para o tipo $tipo.")
        }

        # Ativo
        $ativo = $true
        $ativoEntrada = Get-ValorCampo $Item 'Ativo'
        if ($ativoEntrada -is [bool]) {
            $ativo = $ativoEntrada
        }
        elseif ($null -ne $ativoEntrada -and ([string] $ativoEntrada).Trim() -ne '') {
            switch -Regex (([string] $ativoEntrada).Trim()) {
                '^(true|1|sim|s)$' { $ativo = $true; break }
                '^(false|0|n[aã]o|n)$' { $ativo = $false; break }
                default { $erros.Add("Ativo inválido: '$ativoEntrada'. Use true ou false.") }
            }
        }

        $identificacao = [string] (Get-ValorCampo $Item 'ItemId')
        if ($erros.Count -gt 0) {
            $prefixo = 'Item inválido'
            if ($identificacao) { $prefixo = "Item '$identificacao' inválido" }
            throw "${prefixo}: $($erros -join ' ')"
        }

        [pscustomobject] @{
            ClienteId      = Get-ValorCampo $Item 'ClienteId'
            ItemId         = Get-ValorCampo $Item 'ItemId'
            Tipo           = $tipo
            Alvo           = $alvo
            Descricao      = Get-ValorCampo $Item 'Descricao'
            Titular        = Get-ValorCampo $Item 'Titular'
            DataVencimento = $dataVencimento
            ContatosAlerta = [string[]] $contatos.ToArray()
            Ativo          = $ativo
        }
    }
}

Export-ModuleMember -Function @(
    'Get-DataHojeBrasil'
    'Get-DiasRestantes'
    'Get-MarcoDevido'
    'Test-AlertaPendente'
    'ConvertTo-ItemNormalizado'
)
