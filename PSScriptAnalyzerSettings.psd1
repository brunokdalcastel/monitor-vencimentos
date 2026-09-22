@{
    Severity     = @('Error', 'Warning')

    IncludeDefaultRules = $true

    Rules        = @{
        PSUseCompatibleSyntax          = @{
            Enable         = $true
            TargetVersions = @('7.4', '5.1')
        }

        PSUseCompatibleCmdlets         = @{
            Enable = $false
        }

        PSAvoidUsingWriteHost          = @{
            Enable = $true
        }

        PSAvoidUsingPlainTextForPassword = @{
            Enable = $true
        }

        PSAvoidUsingConvertToSecureStringWithPlainText = @{
            Enable = $true
        }

        PSUseDeclaredVarsMoreThanAssignments = @{
            Enable = $true
        }

        PSProvideCommentHelp           = @{
            Enable = $false
        }
    }
}
