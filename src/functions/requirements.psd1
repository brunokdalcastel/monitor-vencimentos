# Convenção do worker PowerShell do Azure Functions (não é um manifesto de módulo,
# então não tem ModuleVersion/GUID/Author — o ScriptAnalyzer confunde este formato
# com um manifesto de módulo real e aponta PSMissingModuleManifestField; falso
# positivo conhecido, não suprimível por comentário nem atributo num .psd1 que
# precisa continuar sendo só uma hashtable pura (ver Pendências da T08 no PLANO.md).
# Vazio de propósito — managed dependencies desligado (host.json) porque o Flex
# Consumption não suporta módulos pré-instalados (ver ADR 0002). Toda a lógica é
# código próprio em src/modules, sem dependências externas.
@{
}
