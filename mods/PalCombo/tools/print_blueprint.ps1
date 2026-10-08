param(
    [Parameter(Mandatory = $true)][string]$JsonPath,
    [Parameter(Mandatory = $true)][string]$FunctionName
)

$script:Asset = Get-Content -LiteralPath $JsonPath -Raw | ConvertFrom-Json

function Resolve-Index($index) {
    if ($index -gt 0) { return $script:Asset.Exports[$index - 1].ObjectName }
    if ($index -lt 0) { return $script:Asset.Imports[-$index - 1].ObjectName }
    return 'None'
}

function Show-Expr($expr, [int]$depth = 0) {
    if ($null -eq $expr) { return 'null' }
    if ($depth -gt 12) { return '...' }
    if ($expr -is [string] -or $expr -is [ValueType]) { return "$expr" }
    $kind = [string]$expr.'$type' -replace '^.*\.', '' -replace ',.*$', ''
    switch ($kind) {
        {$_ -in @('EX_LocalVariable','EX_LocalOutVariable','EX_InstanceVariable','EX_DefaultVariable')} {
            return ($expr.Variable.New.Path -join '.')
        }
        'EX_Let' { return "$(Show-Expr $expr.Variable ($depth+1)) = $(Show-Expr $expr.Expression ($depth+1))" }
        'EX_LetObj' { return "$(Show-Expr $expr.VariableExpression ($depth+1)) = $(Show-Expr $expr.AssignmentExpression ($depth+1))" }
        'EX_LetBool' { return "$(Show-Expr $expr.VariableExpression ($depth+1)) = $(Show-Expr $expr.AssignmentExpression ($depth+1))" }
        'EX_LetValueOnPersistentFrame' { return "$(($expr.DestinationProperty.New.Path -join '.')) = $(Show-Expr $expr.AssignmentExpression ($depth+1))" }
        'EX_Context' { return "$(Show-Expr $expr.ObjectExpression ($depth+1)).$(Show-Expr $expr.ContextExpression ($depth+1))" }
        'EX_Context_FailSilent' { return "$(Show-Expr $expr.ObjectExpression ($depth+1))?.$(Show-Expr $expr.ContextExpression ($depth+1))" }
        'EX_LocalVirtualFunction' { return "$($expr.VirtualFunctionName)($(($expr.Parameters|ForEach-Object {Show-Expr $_ ($depth+1)}) -join ', '))" }
        'EX_VirtualFunction' { return "$($expr.VirtualFunctionName)($(($expr.Parameters|ForEach-Object {Show-Expr $_ ($depth+1)}) -join ', '))" }
        'EX_FinalFunction' { return "$(Resolve-Index $expr.StackNode)($(($expr.Parameters|ForEach-Object {Show-Expr $_ ($depth+1)}) -join ', '))" }
        'EX_LocalFinalFunction' { return "$(Resolve-Index $expr.StackNode)($(($expr.Parameters|ForEach-Object {Show-Expr $_ ($depth+1)}) -join ', '))" }
        'EX_JumpIfNot' { return "if-not $(Show-Expr $expr.BooleanExpression ($depth+1)) goto $($expr.CodeOffset)" }
        'EX_Jump' { return "goto $($expr.CodeOffset)" }
        'EX_Return' { return "return $(Show-Expr $expr.ReturnExpression ($depth+1))" }
        'EX_IntConst' { return "$($expr.Value)" }
        'EX_IntConstByte' { return "$($expr.Value)" }
        'EX_FloatConst' { return "$($expr.Value)" }
        'EX_DoubleConst' { return "$($expr.Value)" }
        'EX_ByteConst' { return "$($expr.Value)" }
        'EX_NameConst' { return "'$($expr.Value)'" }
        'EX_StringConst' { return "'$($expr.Value)'" }
        'EX_ObjectConst' { return "$(Resolve-Index $expr.Value)" }
        'EX_Self' { return 'self' }
        'EX_True' { return 'true' }
        'EX_False' { return 'false' }
        'EX_NoObject' { return 'null' }
        'EX_Nothing' { return '' }
        'EX_EndOfScript' { return 'end' }
        default {
            $pieces = foreach ($p in $expr.PSObject.Properties) {
                if ($p.Name -in @('$type','Value','Variable','Expression','RValuePointer','PropertyType','Offset')) { continue }
                if ($p.Value -is [System.Array]) {
                    "$($p.Name)=[$(($p.Value|ForEach-Object {Show-Expr $_ ($depth+1)}) -join ', ')]"
                } elseif ($p.Value -is [pscustomobject]) {
                    "$($p.Name)=$(Show-Expr $p.Value ($depth+1))"
                } else {
                    "$($p.Name)=$($p.Value)"
                }
            }
            return "$kind($($pieces -join '; '))"
        }
    }
}

$function = $script:Asset.Exports | Where-Object ObjectName -eq $FunctionName | Select-Object -First 1
if (-not $function) { throw "Function not found: $FunctionName" }
"Function $FunctionName ($($function.ScriptBytecode.Count) statements)"
for ($i = 0; $i -lt $function.ScriptBytecode.Count; $i++) {
    "{0,3}: {1}" -f $i, (Show-Expr $function.ScriptBytecode[$i])
}
