param(
    [Parameter(Mandatory)] [string] $RarsJar,
    [Parameter(Mandatory)] [string] $ImagePath,
    [string] $Java = 'java'
)

$ErrorActionPreference = 'Stop'
$jar = (Resolve-Path -LiteralPath $RarsJar).ProviderPath
$image = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ImagePath)
$imageDirectory = Split-Path -Parent $image
$common = Join-Path $PSScriptRoot 'ram_probe.s'
$rarsSource = Join-Path $PSScriptRoot 'rars_smoke.s'
$fpgaSource = Join-Path $PSScriptRoot 'fpga_smoke.s'

if (-not (Test-Path -LiteralPath $imageDirectory -PathType Container)) {
    throw "Output directory does not exist: $imageDirectory"
}

$runOutput = & $Java '-Djava.awt.headless=true' -jar $jar nc ae1 se2 sm 1000 $rarsSource $common
$runExitCode = $LASTEXITCODE
$runOutput | Write-Output
if ($runExitCode -ne 0 -or 'PASS: stage0 RAM probe' -notin $runOutput) {
    throw "RARS RAM probe failed (exit code $runExitCode)."
}

$tempImage = Join-Path $imageDirectory ('.stage0-' + [Guid]::NewGuid().ToString('N') + '.tmp')
try {
    & $Java '-Djava.awt.headless=true' -jar $jar nc ae1 a mc CompactTextAtZero dump .text HexText $tempImage $fpgaSource $common
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tempImage -PathType Leaf)) {
        throw 'RARS failed to export the FPGA image.'
    }

    $words = [IO.File]::ReadAllLines($tempImage)
    if ($words.Count -lt 1 -or $words.Count -gt 4096 -or $words[0] -ne '00008137' -or
        ($words -notmatch '^[0-9a-fA-F]{8}$').Count -gt 0) {
        throw 'Invalid FPGA ROM image (expected the SP initialization at word 0 and at most 4096 words).'
    }

    # Write a canonical LF-terminated ASCII file on every host.
    [IO.File]::WriteAllText($tempImage, ($words -join "`n") + "`n", [Text.Encoding]::ASCII)
    Move-Item -LiteralPath $tempImage -Destination $image -Force
    Write-Output "ROM_IMAGE $image ($($words.Count) words)"
    Write-Output "SHA256 $((Get-FileHash -LiteralPath $image -Algorithm SHA256).Hash)"
} finally {
    if (Test-Path -LiteralPath $tempImage -PathType Leaf) {
        Remove-Item -LiteralPath $tempImage
    }
}
