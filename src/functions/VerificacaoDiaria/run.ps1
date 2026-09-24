# Function timer (D6: 0 0 11 * * * UTC = 08:00 BRT). Toda a lógica fica em
# src/modules/Orquestrador — este script só chama e registra o resultado.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'Timer', Justification = 'Exigido pelo binding do timerTrigger (function.json); o valor em si não é usado.')]
param($Timer)

$resultado = Invoke-VerificacaoDiaria

Write-Information (
    "Verificação diária concluída: $($resultado.TotalItensVerificados) item(ns) verificado(s), " +
    "$($resultado.AlertasEnviados.Count) alerta(s) enviado(s), $($resultado.Falhas.Count) falha(s)."
) -InformationAction Continue

if ($resultado.Falhas.Count -gt 0) {
    foreach ($falha in $resultado.Falhas) {
        Write-Warning "Falha [$($falha.Tipo)] $($falha.Alvo): $($falha.Erro)"
    }
}
