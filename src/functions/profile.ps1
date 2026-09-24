# profile.ps1 — executado uma vez por cold start do worker PowerShell (ver T08 no PLANO.md).
# Importa o orquestrador (que por sua vez importa Vencimentos/Ssl/Dominio/Storage/Email),
# deixando Invoke-VerificacaoDiaria disponível para qualquer função sem reimportar em cada execução.

Import-Module "$PSScriptRoot/../modules/Orquestrador/Orquestrador.psd1" -Force
