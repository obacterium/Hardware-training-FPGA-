param(
    [Parameter(Mandatory)] [string] $RarsJar,
    [string] $Java = 'java'
)

$ErrorActionPreference = 'Stop'
$jar = (Resolve-Path -LiteralPath $RarsJar).ProviderPath
$sources = 'test_game.s', 'game.s', 'tables.s' | ForEach-Object { Join-Path $PSScriptRoot $_ }
$output = & $Java '-Djava.awt.headless=true' -jar $jar nc ae1 se2 sm 2000000 @sources
$exitCode = $LASTEXITCODE
$output | Write-Output
if ($exitCode -ne 0 -or 'PASS: all stage1 game tests' -notin $output) {
    throw "Stage 1 regression failed (RARS exit code $exitCode)."
}
